#!/usr/bin/env bash
# worker-offline.sh
# Air-gapped version of worker.sh. Run after install-offline-bundle-rhel9.sh.
# Usage: sudo bash worker-offline.sh <path-to-bundle-dir>
#   e.g. sudo bash worker-offline.sh /home/ec2-user/lb-offline-bundle-rhel9

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
rpm --import "$BUNDLE_DIR/rpms/k8s-gpg.key"
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
   echo "Failed to update docker cgroup driver to systemd"
   exit 1
fi

# Containerd needs to be configured to use systemd cgroup driver to align with kubelet's cgroup management.
# The SystemdCgroup setting tells containerd to use systemd to manage container cgroups instead of cgroupfs.
# containerd.io is already installed above via the Docker repo — no separate install needed.
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
sudo systemctl enable --now kubelet
sudo systemctl start kubelet
serviceStatusCheck "kubelet.service" "False"

# Pin packages to avoid auto upgrade.
# On RHEL 9, versionlock is included in python3-dnf-plugins-core (already installed).
sudo dnf versionlock add kubelet kubeadm kubectl docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
