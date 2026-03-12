#!/usr/bin/env bash
# master-offline.sh
# Air-gapped version of master.sh. Run after install-offline-bundle-rhel9.sh.
# Usage: sudo bash master-offline.sh <path-to-bundle-dir>
#   e.g. sudo bash master-offline.sh /home/ec2-user/lb-offline-bundle-rhel9

ULIMIT=1048576

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

BUNDLE_DIR="${1:-}"
if [ -z "$BUNDLE_DIR" ]; then
  echo "Usage: $0 <path-to-bundle-dir>"
  exit 1
fi

if [ ! -d "$BUNDLE_DIR/rpms" ]; then
  echo "ERROR: $BUNDLE_DIR/rpms not found. Is this the correct bundle directory?"
  exit 1
fi

grep -qxF 'export PATH="/usr/local/bin:$PATH"' ~/.bashrc || echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.bashrc
export PATH="/usr/local/bin:$PATH"

echo "Installing Docker and dependencies from local bundle..."
rpm --import "$BUNDLE_DIR/rpms/docker-gpg.key"
dnf install -y --disablerepo='*' --skip-broken "$BUNDLE_DIR"/rpms/*.rpm
sudo systemctl enable --now docker
sudo systemctl start docker

# The Container runtimes explains that the systemd driver is recommended for kubeadm based setups instead of the
# kubelet's default cgroupfs driver, because kubeadm manages the kubelet as a systemd service.
mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF
systemctl restart docker
sleep 10
cgroupdriver_status=`docker info | grep -i "Cgroup Driver"  | grep systemd  | wc -l`
if [ $cgroupdriver_status == 1 ]; then
   echo "Docker cgroup driver is updated to systemd"
else
   echo "Failed to update docker cgroup driver is updated to systemd"
   exit 1
fi
# Set up monthly Docker prune cron job (runs at 3 AM on the 1st of every month)
echo "Setting up Docker prune cron job..."
if ! crontab -l 2>/dev/null | grep -q "docker system prune"; then
  (crontab -l 2>/dev/null; echo "0 3 1 * * /usr/bin/docker system prune -af > /var/log/docker_prune.log 2>&1") | crontab -
  echo "Docker prune cron job added."
else
  echo "Docker prune cron job already exists. Skipping."
fi
# Containerd needs to be configured to use systemd cgroup driver to align with kubelet's cgroup management.
# The SystemdCgroup setting tells containerd to use systemd to manage container cgroups instead of cgroupfs.
# containerd.io is already installed above via the Docker repo — no separate install needed.
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Configure open file descriptor ulimit
# Done here at node setup time so containerd starts with the correct limit
# from the very first launch — no DaemonSet run required after cluster init.
#
# Two settings must be raised in order (each acts as a ceiling for the next):
#   1. fs.nr_open  — kernel hard ceiling; no process can exceed this
#   2. LimitNOFILE — containerd's systemd service limit, inherited by all pods
echo "Configuring open file descriptor ulimit to $ULIMIT..."

# Step 1: raise and persist the kernel ceiling
sysctl -w fs.nr_open=$ULIMIT
sed -i '/^fs\.nr_open/d' /etc/sysctl.conf
echo "fs.nr_open = $ULIMIT" >> /etc/sysctl.conf
echo "  [OK] fs.nr_open set to $ULIMIT"

# Step 2: write the containerd systemd drop-in
mkdir -p /etc/systemd/system/containerd.service.d
cat <<EOF > /etc/systemd/system/containerd.service.d/ulimits.conf
[Service]
LimitNOFILE=$ULIMIT
EOF
echo "  [OK] containerd drop-in written"

# Reload systemd so it picks up the new drop-in before the restart below
systemctl daemon-reload

systemctl restart containerd

# Create the .conf file to load the modules at bootup
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set up required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system
echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables

# Disable Swap Permanently.
swapoff -a                 # Disable all devices marked as swap in /etc/fstab.
sed -e '/swap/ s/^#*/#/' -i /etc/fstab   # Comment the correct mounting point.
systemctl mask swap.target               # Completely disabled.

sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
systemctl disable --now firewalld

TIMEOUT=300
SLEEP_INTERVAL=1

export dotCount=0
export maxDots=15
function showMessage() { # This function prints dots with message and used in a loop while waiting for a condition.
  msg=$1
  dc=$dotCount
  if [ $dc = 0 ]; then
    i=0
    len=${#msg}
    len=$[$len+$maxDots]
    b=""
    while [ $i -ne $len ]
    do
      b="$b "
      i=$[$i+1]
    done
    echo -e -n "\r$b"
    dc=1
  else
    msg="$msg"
    i=0
    while [ $i -ne $dc ]
    do
      msg="$msg."
      i=$[$i+1]
    done
    dc=$[$dc+1]
    if [ $dc = $maxDots ]; then
      dc=0
    fi
  fi
  export dotCount=$dc
  echo -e -n "\r$msg"
}

function serviceStatusCheck() {
    # This function checks service is active or inactive.
    timeCheck=0
    while true
      do
        service=$1
        exit_required=$2
        DOCKER_SERVICE_STATUS="$(systemctl is-active $service)"
        if [ "${DOCKER_SERVICE_STATUS}" = "active" ]; then
          echo ""
          echo "$service running.."
          break
        fi
        showMessage "$service status check"
        sleep $SLEEP_INTERVAL
        timeCheck=$[timeCheck+$SLEEP_INTERVAL]
        if [ $timeCheck -gt $TIMEOUT ]; then
          echo ""
          echo "$service not running, Timeout error."
          echo ""
          if [ "${exit_required}" = "True" ]; then
            exit 1
          fi
        fi
      done
}

echo "Installing kubeadm, kubectl and kubelet from local bundle..."
rpm --import "$BUNDLE_DIR/rpms/k8s-gpg.key"
dnf install -y --disablerepo='*' --skip-broken "$BUNDLE_DIR"/rpms/*.rpm
sudo systemctl enable --now kubelet
sudo systemctl start kubelet &
serviceStatusCheck "kubelet.service" "False"
echo "kubelet Service is $(systemctl is-active kubelet)"
echo "kubeadm reset"
sudo yes | kubeadm reset

echo "Setup helm"
tar -xvf "$BUNDLE_DIR/helm/helm-v3.13.1-linux-amd64.tar.gz" -C /tmp
mv /tmp/linux-amd64/helm /usr/local/bin/helm
chmod +x /usr/local/bin/helm
rm -rf /tmp/linux-amd64
helm version

echo "Initialize kubernetes cluster:"
kubeadm init --pod-network-cidr=192.168.0.0/16 --cri-socket unix:///run/containerd/containerd.sock
rm -rf $HOME/.kube
mkdir -p $HOME/.kube && cp -f /etc/kubernetes/admin.conf $HOME/.kube/config && chown $(id -u):$(id -g) $HOME/.kube/config

echo "Installing network driver:"
kubectl apply -f "$BUNDLE_DIR/manifests/calico.yaml"

while true
  do
    readyNodeCount=$(kubectl get nodes | grep "Ready" | awk '$2' | wc -l)
    if [[ "$readyNodeCount" -ge 1 ]] ; then
      echo "Nodes are ready."
      break
    fi
    showMessage "Checking node status"
    sleep $SLEEP_INTERVAL
    timecheck=$[$timecheck+$SLEEP_INTERVAL]
    if [ $timecheck -gt $TIMEOUT ]; then
      echo ""
      echo "ERROR: Nodes are not ready.. Timeout error."
      echo ""
      exit 1
    fi
  done

# Check calico ippool config, patch vxlanMode to Always if IpIpMode is not allowed.
kubectl wait --for condition=established --timeout=60s crd/ippools.crd.projectcalico.org
IPIP_MODE=$(kubectl get ippool default-ipv4-ippool -o jsonpath='{.spec.ipipMode}')
if [[ "$IPIP_MODE" == "Never" ]]; then
    kubectl patch ippool default-ipv4-ippool --type merge -p '{"spec":{"vxlanMode":"Always"}}'
    echo "Patched vxlanMode to Always"
    kubectl rollout restart daemonset calico-node -n kube-system
    kubectl rollout status daemonset calico-node -n kube-system --timeout=120s
else
    echo "ipipMode is $IPIP_MODE, skipping patch"
fi

# Setup python3.
sudo cp /usr/bin/python3 /usr/local/bin/python

cat <<'EOF' > /usr/local/bin/lightbeam.sh
#!/usr/bin/env bash

trap 'kill $(jobs -p)' EXIT

/usr/bin/kubectl port-forward service/kong-proxy -n lightbeam --address 0.0.0.0 80:80 --kubeconfig /root/.kube/config &
PID1=$!

/usr/bin/kubectl port-forward service/kong-proxy -n lightbeam --address 0.0.0.0 443:443 --kubeconfig /root/.kube/config &
PID2=$!

/bin/systemd-notify --ready

while true; do
    FAIL=0

    kill -0 $PID1
    if [[ $? -ne 0 ]]; then FAIL=1; fi

    kill -0 $PID2
    if [[ $? -ne 0 ]]; then FAIL=1; fi

    status_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/health)
    echo "Lightbeam cluster health check: $status_code"
    if [[ $? -ne 0 || $status_code -ne 200 ]]; then FAIL=1; fi

    if [[ $FAIL -eq 0 ]]; then /bin/systemd-notify WATCHDOG=1; fi

    sleep 1
done
EOF

echo "Script /usr/local/bin/lightbeam.sh has been created."
chmod ugo+x /usr/local/bin/lightbeam.sh

cat <<EOF > /etc/systemd/system/lightbeam.service
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

# Reload systemd, enable and start the service
systemctl daemon-reload
systemctl enable lightbeam.service
systemctl start lightbeam.service

# Set default namespace as lightbeam
kubectl config set-context --current --namespace lightbeam
echo "Done! Ready to deploy LightBeam Cluster!!"

# Pin packages to avoid auto upgrade.
# On RHEL 9, versionlock is included in python3-dnf-plugins-core (already installed).
sudo dnf versionlock add kubelet kubeadm kubectl docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify ulimit was applied correctly
echo ""
echo "=== Ulimit Verification ==="
ACTUAL_NR_OPEN=$(sysctl -n fs.nr_open)
CONTAINERD_PID=$(pidof containerd | cut -d" " -f1)
ACTUAL_LIMIT=$(grep "Max open files" /proc/$CONTAINERD_PID/limits | awk '{print $5}')
echo "  fs.nr_open              : $ACTUAL_NR_OPEN  (expected $ULIMIT)"
echo "  containerd LimitNOFILE  : $ACTUAL_LIMIT  (expected $ULIMIT)"
if [ "$ACTUAL_NR_OPEN" -eq "$ULIMIT" ] && [ "$ACTUAL_LIMIT" -eq "$ULIMIT" ]; then
    echo "  [OK] Ulimit configured correctly."
else
    echo "  [WARN] Ulimit mismatch — check systemd applied the drop-in:"
    echo "         systemctl show containerd | grep LimitNOFILE"
fi
