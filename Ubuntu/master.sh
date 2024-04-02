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

# Disable Swap Permanently.
swapoff -a                 # Disable all devices marked as swap in /etc/fstab.
sed -e '/swap/ s/^#*/#/' -i /etc/fstab   # Comment the correct mounting point.
systemctl mask swap.target               # Completely disabled.

setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
systemctl disable firewalld
systemctl status firewalld
rm /etc/containerd/config.toml
systemctl restart containerd

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
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
apt-get update -y && apt-get install -y kubelet=1.28.8-1.1 kubeadm=1.28.8-1.1 kubectl=1.28.8-1.1
systemctl daemon-reload && systemctl start kubelet && systemctl enable kubelet && systemctl status kubelet
serviceStatusCheck "kubelet.service" "False"

echo "3. Setup helm"
curl -L -O https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz && tar -xvf helm-v3.13.1-linux-amd64.tar.gz && mv linux-amd64/helm /usr/local/bin/ && rm helm-v3.13.1-linux-amd64.tar.gz
helm version

echo "4. Initialize kubernetes cluster:"
kubeadm init --pod-network-cidr=192.168.0.0/16
rm -rf $HOME/.kube
mkdir -p $HOME/.kube && cp -i /etc/kubernetes/admin.conf $HOME/.kube/config && chown $(id -u):$(id -g) $HOME/.kube/config

echo "5. Install network driver:"
curl https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/calico.yaml -O && kubectl apply -f calico.yaml

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
apt install python3-pip -y

# Check if jq is present, if not install it.
if ! command -v jq &> /dev/null; then
    echo "'jq' could not be found, installing it now..."
    # Specify the version you want to install
    JQ_VERSION="1.6"
    # Specify the directory where you want to install jq
    INSTALL_DIR="/usr/local/bin"
    # Determine OS and Architecture for downloading the correct version
    OS=$(uname | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH_SUFFIX="64" ;;
        aarch64) ARCH_SUFFIX="arm64" ;;
        *) echo "Unsupported architecture: $ARCH" ; exit 1 ;;
    esac
    # For Linux x86_64, the suffix is 'linux64', for other OS/architectures, adjust accordingly
    if [ "$OS" == "linux" ] && [ "$ARCH_SUFFIX" == "64" ]; then
        JQ_BINARY="jq-linux64"
    elif [ "$OS" == "linux" ] && [ "$ARCH_SUFFIX" == "arm64" ]; then
        JQ_BINARY="jq-linuxarm64"
    else
        echo "Unsupported OS/Architecture combination: $OS/$ARCH"
        exit 1
    fi
    # Download and install jq
    URL="https://github.com/stedolan/jq/releases/download/jq-${JQ_VERSION}/${JQ_BINARY}"
    sudo wget jq "$URL" -O "${INSTALL_DIR}/jq" && chmod +x "${INSTALL_DIR}/jq"
    echo "'jq' installed successfully."
else
    echo "'jq' is already installed."
fi

# Check if yq is present, if not install it.
if ! command -v yq &> /dev/null; then
    echo "'yq' could not be found, installing it now..."
    # Specify the version you want to install
    YQ_VERSION="v4.6.3"
    # Specify the directory where you want to install yq
    INSTALL_DIR="/usr/local/bin"
    # Determine OS and Architecture for downloading the correct version
    OS=$(uname | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        arm64) ARCH="arm64" ;;
        *) echo "Unsupported architecture: $ARCH" ; exit 1 ;;
    esac
    # Download and install yq
    sudo wget "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_${OS}_${ARCH}" -O "${INSTALL_DIR}/yq" && chmod +x "${INSTALL_DIR}/yq"
    echo "'yq' installed successfully."
else
    echo "'yq' is already installed."
fi

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
