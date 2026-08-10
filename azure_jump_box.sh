#!/usr/bin/env bash

# Initial apt update and install ALL packages at once
sudo apt-get update
sudo apt-get install -y \
    unzip jq apt-transport-https ca-certificates \
    curl gnupg-agent software-properties-common python3-pip

# Setup python3 symlink
sudo cp /usr/bin/python3 /usr/bin/python

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version

# Install helm
wget -q https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz
tar -xf helm-v3.13.1-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/
rm -rf linux-amd64 helm-v3.13.1-linux-amd64.tar.gz

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install terraform CLI
wget -q https://releases.hashicorp.com/terraform/1.7.4/terraform_1.7.4_linux_386.zip
unzip -q terraform_1.7.4_linux_386.zip
sudo mv terraform /usr/local/bin
rm -f terraform_1.7.4_linux_386.zip

# Install Docker
sudo apt-get -y remove docker docker-engine docker.io containerd runc 2>/dev/null || true

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

if systemctl is-active --quiet docker; then
   echo "Docker installed and running .."
else
   echo "Docker installed but not running.."
fi

# Mark packages on hold to avoid auto upgrade (after all packages installed)
sudo apt-mark hold kubelet kubectl kubeadm containerd.io \
    docker-buildx-plugin docker-ce docker-ce-cli docker-ce-rootless-extras \
    docker-compose-plugin snapd systemd systemd-sysv systemd-timesyncd 2>/dev/null || true

# Set the context
kubectl config set-context --current --namespace lightbeam
