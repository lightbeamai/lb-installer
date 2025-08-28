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

setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
systemctl disable firewalld
systemctl status firewalld

# Containerd needs to be configured to use systemd cgroup driver to align with kubelet's cgroup management.
# The SystemdCgroup setting tells containerd to use systemd to manage container cgroups instead of cgroupfs.
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

# Load necessary kernel modules.
modprobe overlay
modprobe br_netfilter

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
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
mkdir -p /etc/apt/keyrings
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
apt-get update -y && apt-get install -y kubelet=1.30.0-1.1 kubeadm=1.30.0-1.1 kubectl=1.30.6-1.1
systemctl daemon-reload && systemctl start kubelet && systemctl enable kubelet && systemctl status kubelet
serviceStatusCheck "kubelet.service" "False"

echo "3. Setup helm"
curl -L -O https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz && tar -xvf helm-v3.13.1-linux-amd64.tar.gz && mv linux-amd64/helm /usr/local/bin/ && rm helm-v3.13.1-linux-amd64.tar.gz
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
rm -rf $HOME/.kube
mkdir -p $HOME/.kube && cp -i /etc/kubernetes/admin.conf $HOME/.kube/config && chown $(id -u):$(id -g) $HOME/.kube/config

echo "5. Install network driver:"
curl https://raw.githubusercontent.com/projectcalico/calico/v3.29.0/manifests/calico.yaml -O && kubectl apply -f calico.yaml

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

# Setup python3.
cp /usr/bin/python3 /usr/bin/python
apt install python3-pip python3-virtualenv -y 

# Mark packages on hold to avoid an auto upgrade.
apt-mark hold kubelet
apt-mark hold kubectl
apt-mark hold kubeadm
apt-mark hold containerd.io
apt-mark hold docker-buildx-plugin
apt-mark hold docker-ce
apt-mark hold docker-cli
apt-mark hold docker-ce-rootless-extras
apt-mark hold docker-compose-plugin
apt-mark hold snapd
apt-mark hold systemd
apt-mark hold systemd-sysv
apt-mark hold systemd-timesyncd

# set default namespace as lightbeam
kubectl config set-context --current --namespace lightbeam
echo "Done! Ready to deploy LightBeam Cluster!!"

# Linux Command History with date and time
echo 'export HISTTIMEFORMAT="%d/%m/%y %T "' >> ~/.bash_profile

# set common alias
echo "alias k=kubectl" >> ~/.bashrc
