#!/bin/bash
# worker_edge_kubernetes.sh — Kubernetes join for edge worker nodes.
#
# Sourced by worker_edge.sh after WireGuard is established.
# Expects env vars from edge-config.env and functions from ph2_common.sh.

set -euo pipefail

JOIN_WAIT_SECONDS=300
JOIN_POLL_SECONDS=10

wait_for_node_registration() {
  local node_name
  local elapsed=0

  node_name="${NODE_NAME:-$(hostname -s)}"
  log_step "Validate Kubernetes Join"
  echo "Waiting for kubeadm join to register node ${node_name}..."
  while (( elapsed < JOIN_WAIT_SECONDS )); do
    if [[ -f /etc/kubernetes/kubelet.conf ]]; then
      echo "Validation: kubelet bootstrap config exists"
      if kubectl --kubeconfig /etc/kubernetes/kubelet.conf get node "$node_name" >/dev/null 2>&1; then
        echo "✓ Node ${node_name} is registered with the cluster"
        echo "Validation: kubeadm join completed successfully"
        return 0
      fi
    fi

    echo "Node registration not visible yet (${elapsed}s elapsed)..."
    sleep "$JOIN_POLL_SECONDS"
    elapsed=$((elapsed + JOIN_POLL_SECONDS))
  done

  echo "ERROR: Timed out waiting for kubeadm join to register node ${node_name}"
  return 1
}

# --- Execute ---

if [[ "${JOIN_COMMAND}" != kubeadm\ join* ]]; then
  echo "ERROR: join_command must start with 'kubeadm join'"
  exit 1
fi

TOKEN_VALUE=$(printf '%s\n' "${JOIN_COMMAND}" | sed -nE 's/.*--token[[:space:]]+([^[:space:]]+).*/\1/p')
if [[ -z "${TOKEN_VALUE}" ]]; then
  echo "ERROR: could not extract bootstrap token from join_command"
  exit 1
fi

if [[ -z "${CONTROL_PLANE_CA_CERT}" ]]; then
  echo "ERROR: control_plane_ca_cert is empty"
  exit 1
fi

# Use short hostname as node name to stay under 63-char K8s limit
# GCP FQDNs like "hstest-gcp-edge-us-east1-b-1.us-east1-b.c.lightbeam-dev.internal" are too long
NODE_NAME=$(hostname -s)
echo "Node name: ${NODE_NAME}"

mkdir -p /etc/default
cat > /etc/default/kubelet <<EOF_KUBELET
KUBELET_EXTRA_ARGS=--node-ip=${WIREGUARD_NODE_IP} --hostname-override=${NODE_NAME}
EOF_KUBELET
systemctl daemon-reload
systemctl restart kubelet || true

DISCOVERY_KUBECONFIG_SCRIPT="${SCRIPT_DIR}/discovery-kubeconfig.sh"
if [[ ! -x "${DISCOVERY_KUBECONFIG_SCRIPT}" ]]; then
  echo "ERROR: ${DISCOVERY_KUBECONFIG_SCRIPT} is missing or not executable"
  exit 1
fi

echo "Generating discovery kubeconfig via ${DISCOVERY_KUBECONFIG_SCRIPT}..."
"${DISCOVERY_KUBECONFIG_SCRIPT}" \
  --control-plane-ip "${WIREGUARD_CONTROL_PLANE_IP}" \
  --token "${TOKEN_VALUE}" \
  --ca-cert "${CONTROL_PLANE_CA_CERT}" \
  --output "/root/discovery-kubeconfig.yaml"

echo "Using join command against WireGuard-connected control plane"
echo "Join endpoint: ${WIREGUARD_CONTROL_PLANE_IP}:6443"
echo "Node IP: ${WIREGUARD_NODE_IP}"
echo "Confirmed tunnel and API are up; proceeding with kubeadm join"
if [[ -f /etc/kubernetes/kubelet.conf || -f /etc/kubernetes/bootstrap-kubelet.conf || -f /etc/kubernetes/pki/ca.crt ]]; then
  echo "Stale kubeadm state detected; running kubeadm reset before join..."
  kubeadm reset -f
fi
echo "Executing kubeadm join with discovery file..."
kubeadm join --discovery-file /root/discovery-kubeconfig.yaml --node-name "${NODE_NAME}"
wait_for_node_registration
