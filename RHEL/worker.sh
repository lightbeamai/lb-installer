#!/usr/bin/env bash

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit
fi

echo "Installing docker"
sudo dnf config-manager --add-repo=https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
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

echo "Installing containerd"
sudo yum install containerd vim -y
sudo systemctl enable containerd
sudo systemctl start containerd
# Containerd needs to be configured to use systemd cgroup driver to align with kubelet's cgroup management.
# The SystemdCgroup setting tells containerd to use systemd to manage container cgroups instead of cgroupfs.
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
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
setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables

# Disable Swap Permanently.
swapoff -a                 # Disable all devices marked as swap in /etc/fstab.
sed -e '/swap/ s/^#*/#/' -i /etc/fstab   # Comment the correct mounting point.
systemctl mask swap.target               # Completely disabled.

sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
systemctl disable firewalld
systemctl status firewalld

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

dnf makecache
dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

echo "Installing kubeadm, kubectl and kubelet:"
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.32/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.32/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
sudo dnf install -y kubelet-1.32.0 kubeadm-1.32.0 kubectl-1.32.0 --disableexcludes=kubernetes
sudo systemctl enable --now kubelet
sudo systemctl start kubelet

# Mark packages on hold to avoid an auto upgrade.
sudo dnf mark install kubelet kubeadm kubectl docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
