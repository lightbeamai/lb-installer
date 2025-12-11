#!/usr/bin/env bash

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit
fi

TIMEOUT=300
SLEEP_INTERVAL=1

# Remove all older packages.
apt-get -y remove docker docker-engine docker.io containerd runc kubeadm kubelet kubectl

# Install docker.
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common openssh-server

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

add-apt-repository -y \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

apt-get update -y
apt-get install docker-ce docker-ce-cli containerd.io -y
docker_status=`systemctl status docker | grep "running" | wc -l`
echo "$docker_status"
if [ $docker_status == 1 ]; then
   echo "Docker installed and running .."
else
   echo "Docker installed but not running.."
fi

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

# Disable Swap Permanently.
swapoff -a                 # Disable all devices marked as swap in /etc/fstab.
sed -e '/swap/ s/^#*/#/' -i /etc/fstab   # Comment the correct mounting point.
systemctl mask swap.target               # Completely disabled.

# SELinux is not default on Ubuntu, but disable if present
if command -v setenforce >/dev/null 2>&1; then
    setenforce 0
    sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
fi

# Ubuntu uses ufw, not firewalld by default
if systemctl is-enabled ufw >/dev/null 2>&1; then
    ufw disable
else
    echo "UFW not enabled, skipping firewall disable"
fi

# Containerd needs to be configured to use systemd cgroup driver to align with kubelet's cgroup management.
# The SystemdCgroup setting tells containerd to use systemd to manage container cgroups instead of cgroupfs.
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

# Load necessary kernel modules.
modprobe overlay
modprobe br_netfilter

# Make kernel modules persistent
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# Set required sysctl parameters.
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

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
        # Strip ANSI escape sequences and get clean output
        DOCKER_SERVICE_STATUS="$(systemctl is-active $service 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r')"
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
          break
        fi
      done
}

echo "2. Install kubeadm, kubectl and kubelet:"

# Complete cleanup first
rm -f /etc/apt/sources.list.d/kubernetes.list
rm -rf /etc/apt/keyrings
apt-get clean

# Install required packages
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gpg

# Create keyrings directory
mkdir -p /etc/apt/keyrings

# Download Kubernetes signing key (method that avoids control characters)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key -o /tmp/k8s-key.gpg
gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg /tmp/k8s-key.gpg
rm -f /tmp/k8s-key.gpg

# Create repository file manually (avoids echo/tee control character issues)
cat > /etc/apt/sources.list.d/kubernetes.list << 'REPO_EOF'
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /
REPO_EOF

# Update package index
apt-get update -y

# Install Kubernetes components with specific versions
apt-get install -y kubelet=1.30.0-1.1 kubeadm=1.30.0-1.1 kubectl=1.30.6-1.1

# Enable and start kubelet
systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet

# Check kubelet status (it's normal for kubelet to be in crash loop before cluster init)
echo "Note: kubelet may show as failed until cluster is initialized - this is normal"
systemctl status kubelet --no-pager -l

echo "3. Setup helm"
curl -L -O https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz && tar -xvf helm-v3.13.1-linux-amd64.tar.gz && mv linux-amd64/helm /usr/local/bin/ && rm -rf helm-v3.13.1-linux-amd64.tar.gz linux-amd64
helm version

echo "4. Initialize kubernetes cluster:"
# Create the kubeadm config file with hardened security settings
cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  kubeletExtraArgs:
    cgroup-driver: "systemd"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: "v1.30.0"
networking:
  serviceSubnet: "10.200.0.0/16"
  podSubnet: "192.168.0.0/16"
apiServer:
  extraArgs:
    tls-min-version: "VersionTLS12"
    tls-cipher-suites: "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,TLS_AES_256_GCM_SHA384,TLS_AES_128_GCM_SHA256,TLS_CHACHA20_POLY1305_SHA256"
etcd:
  local:
    extraArgs:
      cipher-suites: "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
EOF

kubeadm init --config kubeadm-config.yaml 

# Setup kubectl for root user
rm -rf $HOME/.kube
mkdir -p $HOME/.kube && cp -i /etc/kubernetes/admin.conf $HOME/.kube/config && chown $(id -u):$(id -g) $HOME/.kube/config

echo "5. Install network driver:"
# Use the latest Calico version compatible with Kubernetes 1.30
curl https://raw.githubusercontent.com/projectcalico/calico/v3.29.0/manifests/calico.yaml -O && kubectl apply -f calico.yaml

# Wait for nodes to be ready
timecheck=0
while true
  do
    readyNodeCount=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
    if [[ "$readyNodeCount" -ge 1 ]] ; then
      echo ""
      echo "Nodes are ready."
      kubectl get nodes
      break
    fi
    showMessage "Checking node status"
    sleep $SLEEP_INTERVAL
    timecheck=$[$timecheck+$SLEEP_INTERVAL]
    if [ $timecheck -gt $TIMEOUT ]; then
      echo ""
      echo "ERROR: Nodes are not ready.. Timeout error."
      echo ""
      kubectl get nodes
      exit 1
    fi
  done

# Setup python3 - Ubuntu 24.04 may not have python3 symlinked to python
if [ ! -f /usr/bin/python ]; then
    ln -s /usr/bin/python3 /usr/bin/python
fi
apt install python3-pip python3-virtualenv -y 

# Mark packages on hold to avoid an auto upgrade.
apt-mark hold kubelet
apt-mark hold kubectl
apt-mark hold kubeadm
apt-mark hold containerd.io
apt-mark hold docker-buildx-plugin
apt-mark hold docker-ce
apt-mark hold docker-ce-cli
apt-mark hold docker-ce-rootless-extras
apt-mark hold docker-compose-plugin
apt-mark hold snapd
apt-mark hold systemd
apt-mark hold systemd-sysv
apt-mark hold systemd-timesyncd

# Create lightbeam namespace if it doesn't exist
kubectl create namespace lightbeam --dry-run=client -o yaml | kubectl apply -f -

# Set default namespace as lightbeam
kubectl config set-context --current --namespace=lightbeam

echo "Done! Ready to deploy LightBeam Cluster!!"

# Linux Command History with date and time and common aliases
echo 'export HISTTIMEFORMAT="%d/%m/%y %T "' >> ~/.bashrc
echo 'export HISTSIZE=10000' >> ~/.bashrc          # Keep 10,000 commands in memory
echo 'export HISTFILESIZE=10000' >> ~/.bashrc      # Keep 10,000 commands in history file
echo 'export HISTCONTROL=ignoreboth' >> ~/.bashrc  # Ignore duplicates and commands starting with space
echo 'shopt -s histappend' >> ~/.bashrc            # Append to history file, don't overwrite
echo "alias k=kubectl" >> ~/.bashrc

# Display cluster info
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

# --- KUBECTL AUTOCOMPLETE SETUP ---

# Ensure bash-completion is available
if ! type _init_completion >/dev/null 2>&1; then
    # Try to install if system is Debian/Ubuntu
    if [ -f /etc/debian_version ]; then
        echo "Installing bash-completion..."
        sudo apt-get update -y
        sudo apt-get install -y bash-completion
    else
        echo "bash-completion not installed and cannot auto-install."
    fi
fi

# Load bash-completion if present
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
elif [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
fi

# Enable kubectl autocompletion
if command -v kubectl >/dev/null 2>&1; then
    source <(kubectl completion bash)
else
    echo "kubectl not found in PATH. Autocomplete not enabled."
fi

# Optional: Add 'k' alias
alias k=kubectl
complete -o default -F __start_kubectl k

# --- END AUTOCOMPLETE SETUP ---
