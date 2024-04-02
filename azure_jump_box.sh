#!/usr/bin/env bash

sudo apt-get update
sudo apt-get install -y unzip jq

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version

wget https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz
tar -xvf helm-v3.13.1-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/

sudo curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

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

sudo add-apt-repository -y\
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

# Setup terraform CLI.
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl
wget https://releases.hashicorp.com/terraform/1.7.4/terraform_1.7.4_linux_386.zip
unzip terraform_1.7.4_linux_386.zip
sudo mv terraform /usr/local/bin

# Setup python3.
sudo cp /usr/bin/python3 /usr/bin/python
sudo apt install -y python3-pip

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
