#!/usr/bin/env bash

echo "Installing podman podman-docker iproute-tc"
sudo yum install -y iproute-tc podman podman-docker vim

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
swapoff -a
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
systemctl disable firewalld
systemctl status firewalld

export VERSION=1.21
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_8/devel:kubic:libcontainers:stable.repo
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/CentOS_8/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo
sudo yum install cri-o -y

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



sudo systemctl enable --now cri-o
sudo systemctl start cri-o



cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF



yum install -y kubelet-1.21.0-0.x86_64 kubeadm-1.21.0-0.x86_64 kubectl-1.21.0-0.x86_64



sudo systemctl enable --now kubelet
sudo systemctl start kubelet &

serviceStatusCheck "kubelet.service" "False"


echo "kubelet Service is $(systemctl is-active kubelet)"
echo "kubeadm reset"
sudo yes | kubeadm reset

sudo kubeadm init --pod-network-cidr=192.168.0.0/16

mkdir -p /root/.kube
sudo yes | cp -i /etc/kubernetes/admin.conf /root/.kube/config
sudo chown $(id -u):$(id -g) /root/.kube/config

kubectl taint nodes --all node-role.kubernetes.io/master-
kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml
kubectl create -f https://docs.projectcalico.org/manifests/custom-resources.yaml

echo "3. Setup helm"
sudo curl -L -O https://get.helm.sh/helm-v3.3.4-linux-amd64.tar.gz && sudo tar -xvf helm-v3.3.4-linux-amd64.tar.gz && sudo mv linux-amd64/helm /usr/bin/ && sudo rm helm-v3.3.4-linux-amd64.tar.gz
helm version

