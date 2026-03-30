#!/bin/bash
# master_kubernetes.sh — Initialize the Kubernetes control plane, install Calico
# CNI, configure the Lightbeam service, set up NAT, preserve WireGuard client
# configs, generate edge-node join scripts, and install supporting tools.
#
# Sourced by master_common.sh after master_install.sh.

set -euo pipefail

normalize_ipv4() {
  local raw="${1:-}"
  local candidate
  candidate="$(printf '%s' "$raw" | tr -d '\r' | awk '{print $1}')"
  if [[ "$candidate" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  printf '%s\n' ""
}

# ---------------------------------------------------------------------------
# kubeadm init
# ---------------------------------------------------------------------------

log_step "Initialize Kubernetes control plane"
PRIVATE_IP="$(normalize_ipv4 "${PRIVATE_IP:-}")"
PUBLIC_IP="$(normalize_ipv4 "${PUBLIC_IP:-}")"
WG_IP="$(normalize_ipv4 "${WG_IP:-}")"

if [[ -z "${PRIVATE_IP:-}" ]]; then
  echo "ERROR: PRIVATE_IP is empty; cannot generate kubeadm config."
  exit 1
fi
if [[ -z "${PUBLIC_IP:-}" ]]; then
  PUBLIC_IP="$PRIVATE_IP"
fi
if [[ -z "${WG_IP:-}" ]]; then
  WG_IP=$(awk -F'=' '/^[[:space:]]*Address[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); split($2,a,"/"); print a[1]; exit}' /etc/wireguard/wg0.conf || true)
fi
WG_IP="$(normalize_ipv4 "${WG_IP:-}")"
if [[ -z "${WG_IP:-}" ]]; then
  WG_IP="$PRIVATE_IP"
fi
cat > /root/kubeadm-config.yaml <<KUBEADM_EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "$PRIVATE_IP"
  bindPort: 6443
nodeRegistration:
  kubeletExtraArgs:
    cgroup-driver: "systemd"
    node-ip: "$PRIVATE_IP"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: "v1.33.0"
controlPlaneEndpoint: "$PRIVATE_IP:6443"
networking:
  serviceSubnet: "10.200.0.0/16"
  podSubnet: "10.244.0.0/16"
apiServer:
  certSANs:
  - "$PRIVATE_IP"
  - "$PUBLIC_IP"
  - "$WG_IP"
  - "10.200.0.1"
KUBEADM_EOF

CP_ALREADY_READY="false"
if [[ -f /etc/kubernetes/admin.conf ]]; then
  echo "Existing control plane state detected; verifying API server health..."
  attempts=0
  max_attempts=24
  while [[ $attempts -lt $max_attempts ]]; do
    if kubectl --kubeconfig /etc/kubernetes/admin.conf cluster-info >/dev/null 2>&1; then
      CP_ALREADY_READY="true"
      break
    fi
    attempts=$((attempts + 1))
    sleep 5
  done
fi

if [[ "$CP_ALREADY_READY" == "true" ]]; then
  echo "Existing control plane detected (/etc/kubernetes/admin.conf present and API reachable); skipping kubeadm init."
elif [[ -f /etc/kubernetes/admin.conf ]]; then
  echo "ERROR: Found /etc/kubernetes/admin.conf but API server is not reachable."
  echo "ERROR: Stale or partial control-plane state detected."
  echo "Recovery:"
  echo "  kubeadm reset -f"
  echo "  rm -rf /etc/kubernetes/manifests/* /var/lib/etcd"
  echo "Then rerun the installer."
  exit 1
else
  kubeadm init --config /root/kubeadm-config.yaml
fi

mkdir -p /root/.kube && cp /etc/kubernetes/admin.conf /root/.kube/config && chown root:root /root/.kube/config
chmod 600 /root/.kube/config

if [[ ! -s /root/.kube/config ]]; then
    echo "ERROR: /root/.kube/config was not created correctly"
    exit 1
fi

export KUBECONFIG=/root/.kube/config
grep -qxF 'export KUBECONFIG=/root/.kube/config' /root/.bashrc || echo 'export KUBECONFIG=/root/.kube/config' >> /root/.bashrc

# Make kubectl work in future shells for both root and OS Login users.
cat > /etc/profile.d/lightbeam-kube.sh <<'PROFILE_EOF'
export PATH="/usr/bin:$PATH"

if [ "$(id -u)" -eq 0 ] && [ -z "${KUBECONFIG:-}" ] && [ -f /root/.kube/config ]; then
  export KUBECONFIG=/root/.kube/config
fi

if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
  kubectl() {
    sudo /usr/bin/kubectl --kubeconfig /etc/kubernetes/admin.conf "$@"
  }

  k() {
    kubectl "$@"
  }
fi
PROFILE_EOF
chmod 644 /etc/profile.d/lightbeam-kube.sh

if ! kubectl --kubeconfig /root/.kube/config cluster-info >/dev/null 2>&1; then
    echo "ERROR: kubectl could not talk to the API server using /root/.kube/config"
    exit 1
fi

echo "Waiting for Kubernetes API server to be ready..."
max_attempts=60
attempt=0
while ! kubectl cluster-info &> /dev/null; do
  attempt=$((attempt + 1))
  if [ $attempt -ge $max_attempts ]; then
    echo "ERROR: Kubernetes API server not ready after $max_attempts attempts"
    exit 1
  fi
  echo "Attempt $attempt/$max_attempts: Waiting for API server..."
  sleep 5
done
echo "Kubernetes API server is ready!"
kubectl get nodes || true

# ---------------------------------------------------------------------------
# Join command
# ---------------------------------------------------------------------------

log_step "Generate worker join command"
echo "Generating cluster join command..."
JOIN_COMMAND=$(kubeadm token create --print-join-command)
echo "Join command generated: $JOIN_COMMAND"
echo "$JOIN_COMMAND" > /root/join-command.txt
chmod 600 /root/join-command.txt
echo "Join command saved to /root/join-command.txt"

# ---------------------------------------------------------------------------
# Calico CNI
# ---------------------------------------------------------------------------

log_step "Install Calico CNI"
kubectl apply -f "${SCRIPT_DIR}/calico.yaml"

echo "Waiting for Calico pods to be ready on control plane..."

kubectl set env daemonset/calico-node -n kube-system IP_AUTODETECTION_METHOD=cidr=10.100.0.0/16

# Wait for the calico-node pod on this node (not all nodes — workers haven't joined yet)
NODE_NAME=$(hostname)
CALICO_TIMEOUT=300
CALICO_ELAPSED=0
while (( CALICO_ELAPSED < CALICO_TIMEOUT )); do
  CALICO_READY=$(kubectl -n kube-system get pods -l k8s-app=calico-node \
    --field-selector "spec.nodeName=${NODE_NAME}" \
    -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  if [[ "$CALICO_READY" == "True" ]]; then
    echo "✓ calico-node pod ready on ${NODE_NAME}"
    break
  fi
  echo "Waiting for calico-node on ${NODE_NAME}... (${CALICO_ELAPSED}s)"
  sleep 10
  CALICO_ELAPSED=$((CALICO_ELAPSED + 10))
done
if [[ "$CALICO_READY" != "True" ]]; then
  echo "ERROR: calico-node pod not ready on ${NODE_NAME} after ${CALICO_TIMEOUT}s"
  kubectl -n kube-system get pods -l k8s-app=calico-node -o wide || true
  kubectl -n kube-system logs -l k8s-app=calico-node --all-containers=true --tail=100 || true
  exit 1
fi

if ! kubectl -n kube-system rollout status deployment/calico-kube-controllers --timeout=300s; then
    echo "ERROR: calico-kube-controllers Deployment did not become ready."
    kubectl -n kube-system get pods -l k8s-app=calico-kube-controllers -o wide || true
    kubectl -n kube-system logs -l k8s-app=calico-kube-controllers --all-containers=true --tail=200 || true
    exit 1
fi

kubectl create namespace lightbeam --dry-run=client -o yaml | kubectl apply -f -
kubectl config set-context --current --namespace=lightbeam
echo "Done! Ready to deploy LightBeam Cluster!!"

# ---------------------------------------------------------------------------
# Lightbeam systemd service
# ---------------------------------------------------------------------------

log_step "Configure Lightbeam systemd service"
tee /usr/local/bin/lightbeam.sh > /dev/null <<'EOF'
#!/usr/bin/env bash

trap 'kill $(jobs -p)' EXIT
/usr/bin/kubectl port-forward service/kong-proxy -n lightbeam --address 0.0.0.0 80:80 443:443 --kubeconfig /root/.kube/config &
PID=$!

/bin/systemd-notify --ready

while(true); do
    FAIL=0
    kill -0 $PID
    if [[ $? -ne 0 ]]; then FAIL=1; fi

    status_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/health)
    curl_exit=$?
    echo "Lightbeam cluster health check: $status_code (curl exit: $curl_exit)"
    if [[ $curl_exit -ne 0 || ( $status_code -ne 200 && $status_code -ne 301 ) ]]; then
        FAIL=1
    fi

    if [[ $FAIL -eq 0 ]]; then /bin/systemd-notify WATCHDOG=1; fi
    sleep 1
done
EOF
chmod ugo+x /usr/local/bin/lightbeam.sh

tee /etc/systemd/system/lightbeam.service > /dev/null <<'EOF'
[Unit]
Description=LightBeam Application
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

StartLimitIntervalSec=500
StartLimitBurst=10000

[Service]
Type=notify
Restart=always
RestartSec=1
TimeoutSec=5
WatchdogSec=5
ExecStart=/usr/local/bin/lightbeam.sh

[Install]
WantedBy=multi-user.target
EOF

echo "Systemd service file /etc/systemd/system/lightbeam.service has been created."
systemctl daemon-reload
systemctl enable lightbeam.service
systemctl start lightbeam.service

# ---------------------------------------------------------------------------
# NAT and iptables
# ---------------------------------------------------------------------------

log_step "Configure NAT and persistent iptables"
PRIMARY_IFACE=$(ip route | grep default | awk '{print $5}')
iptables -t nat -A POSTROUTING -o "$PRIMARY_IFACE" -j MASQUERADE
iptables -A FORWARD -i "$PRIMARY_IFACE" -o "$PRIMARY_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i "$PRIMARY_IFACE" -o "$PRIMARY_IFACE" -j ACCEPT

# Save iptables rules (iptables-persistent/iptables-services installed in phase 1)
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save
elif [ -f /etc/sysconfig/iptables ]; then
  iptables-save > /etc/sysconfig/iptables
  systemctl restart iptables || true
fi

# ---------------------------------------------------------------------------
# WireGuard client configs and edge-node scripts
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# udp2raw (UDP over TCP tunneling) — skipped on AWS (runs on gateway instead)
# ---------------------------------------------------------------------------

if [[ "${SKIP_WIREGUARD:-false}" != "true" ]]; then
  if systemctl is-active --quiet udp2raw.service; then
    systemctl stop udp2raw.service || true
  fi
  if ! command -v udp2raw >/dev/null 2>&1; then
    if [[ -f /tmp/udp2raw_amd64 ]]; then
      install -m 755 /tmp/udp2raw_amd64 /usr/local/bin/udp2raw
      rm -f /tmp/udp2raw_binaries.tar.gz /tmp/udp2raw_amd64
    else
      echo "ERROR: udp2raw not installed and /tmp/udp2raw_amd64 not found"
      exit 1
    fi
  fi

  cat > /etc/udp2raw.conf <<EOF
-s
-l 0.0.0.0:51821
-r 127.0.0.1:51820
-k "lightbeam"
--raw-mode faketcp
-a
EOF
  chmod 600 /etc/udp2raw.conf

  cat << 'EOF' > /etc/systemd/system/udp2raw.service
[Unit]
Description=udp2raw service
ConditionFileIsExecutable=/usr/local/bin/udp2raw
ConditionPathExists=/etc/udp2raw.conf
After=network.target
[Service]
Type=simple
User=root
Group=root
PIDFile=/run/udp2raw.pid
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
ExecStart=/usr/local/bin/udp2raw --conf-file /etc/udp2raw.conf
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now udp2raw.service
fi

# ---------------------------------------------------------------------------
# allssh helper
# ---------------------------------------------------------------------------

cat << 'EOF' > /usr/local/bin/allssh
#!/bin/bash
node_ips=($(kubectl get nodes -o wide --no-headers | awk '{print $6}'))

if [ $# -eq 0 ]; then
  echo "Usage: allssh <command>"
  exit 1
fi

for ip in "${node_ips[@]}"; do
  echo "Running on node: $ip"
  ssh "$ip" "$@"
  echo "===================="
done
EOF
chmod ugo+x /usr/local/bin/allssh

# ---------------------------------------------------------------------------
# Final cluster status
# ---------------------------------------------------------------------------

echo ""
echo "=== Cluster Information ==="
kubectl cluster-info
echo ""
echo "=== Node Status ==="
kubectl get nodes -o wide
echo ""
echo "=== System Pods ==="
kubectl get pods -n kube-system
kubectl config set-context --current --namespace=lightbeam

echo "=== MASTER NODE SETUP COMPLETE ==="
echo "Kubernetes Version: $(kubectl version --short 2>/dev/null || kubectl version)"
echo "Docker Version: $(docker --version)"
echo "Calico Version: v3.30.0"
echo ""
JOIN_TOKEN_STORE_REF="${TOKEN_STORE_NAME:-}"
if [[ -z "${JOIN_TOKEN_STORE_REF:-}" ]] && declare -F token_store_aws_name >/dev/null 2>&1; then
  JOIN_TOKEN_STORE_REF="$(token_store_aws_name 2>/dev/null || true)"
fi
if [[ -z "${JOIN_TOKEN_STORE_REF:-}" ]] && declare -F token_store_gcp_secret_name >/dev/null 2>&1; then
  JOIN_TOKEN_STORE_REF="$(token_store_gcp_secret_name 2>/dev/null || true)"
fi
if [[ -z "${JOIN_TOKEN_STORE_REF:-}" ]]; then
  JOIN_TOKEN_STORE_REF="/lightbeam/cluster-token"
fi
echo "Join command token store location: ${JOIN_TOKEN_STORE_REF}"
