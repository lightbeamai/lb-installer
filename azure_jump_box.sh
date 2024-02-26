#!/usr/bin/env bash

sudo apt-get update
sudo apt-get install -y unzip jq

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version

wget https://get.helm.sh/helm-v3.3.4-linux-amd64.tar.gz
tar -xvf helm-v3.3.4-linux-amd64.tar.gz
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
