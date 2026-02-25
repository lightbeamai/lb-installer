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
apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common openssh-server apt-transport-https curl

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

add-apt-repository \
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

mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF
systemctl restart docker
sleep 10
cgroup_driver_status=`docker info | grep -i "Cgroup Driver"  | grep systemd  | wc -l`
if [ $cgroup_driver_status == 1 ]; then
   echo "Docker cgroup driver is updated to systemd"
else
   echo "Failed to update docker cgroup driver is updated to systemd"
   exit 1
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
    systemctl status ufw
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
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
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

echo "2. Install kubeadm, kubectl and kubelet for Kubernetes 1.33:"

# Complete cleanup first
rm -f /etc/apt/sources.list.d/kubernetes.list
rm -rf /etc/apt/keyrings
apt-get clean

# Install required packages
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gpg

# Create keyrings directory
mkdir -p /etc/apt/keyrings

# Download Kubernetes signing key for v1.33
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Create repository file for v1.33
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update package index
apt-get update -y

# Install Kubernetes 1.33 components
apt-get install -y kubelet=1.33.0-1.1 kubeadm=1.33.0-1.1 kubectl=1.33.0-1.1

# Enable and start kubelet
systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet

# Check kubelet status (it's normal for kubelet to be in crash loop before cluster init)
echo "Note: kubelet may show as failed until cluster is initialized - this is normal"
systemctl status kubelet --no-pager -l

serviceStatusCheck "kubelet.service" "False"

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
