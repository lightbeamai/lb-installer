#!/usr/bin/env bash

# Mark packages on hold to avoid auto upgrade.
sudo apt-mark hold kubelet
sudo apt-mark hold kubectl
sudo apt-mark hold kubeadm
sudo apt-mark hold containerd.io
sudo apt-mark hold docker-buildx-plugin
sudo apt-mark hold docker-ce
sudo apt-mark hold docker-cli
sudo apt-mark hold docker-ce-rootless-extras
sudo apt-mark hold docker-compose-plugin
sudo apt-mark hold snapd
sudo apt-mark hold systemd
sudo apt-mark hold systemd-sysv
sudo apt-mark hold systemd-timesyncd

TIMEOUT=300
SLEEP_INTERVAL=1

# Install docker.
sudo apt-get -y remove docker docker-engine docker.io containerd runc
sudo apt-get update -y
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

sudo apt-get update -y
sudo apt-get install docker-ce docker-ce-cli containerd.io -y
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
sudo swapoff -a                 # Disable all devices marked as swap in /etc/fstab.
sudo sed -e '/swap/ s/^#*/#/' -i /etc/fstab   # Comment the correct mounting point.
sudo systemctl mask swap.target               # Completely disabled.

sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
sudo systemctl disable firewalld
sudo systemctl status firewalld
sudo rm /etc/containerd/config.toml
sudo systemctl restart containerd

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

echo "2. Install kubeadm, kubectl and kubelet:"
apt-get update -y && apt-get install -y openssh-server apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update -y && apt-get install -y kubelet=1.23.0-00 kubeadm=1.23.0-00 kubectl=1.23.0-00
systemctl daemon-reload && systemctl start kubelet && systemctl enable kubelet && systemctl status kubelet
serviceStatusCheck "kubelet.service" "False"
