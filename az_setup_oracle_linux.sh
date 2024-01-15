#!/usr/bin/env bash

# This script is used to setup all LightBeam Jumpbox required packages on Oracle Linux 8.

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit
fi

# Setup kubectl.
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version

# Install helm.
wget https://get.helm.sh/helm-v3.3.4-linux-amd64.tar.gz
tar -xvf helm-v3.3.4-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/

# Install az-cli.
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
sudo dnf install azure-cli

# Install docker.
dnf install -y dnf-utils zip unzip
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
dnf remove -y runc
dnf install -y docker-ce --nobest
systemctl enable docker.service
systemctl start docker.service
systemctl status docker.service

# Install and setup system activity report
sudo dnf install sysstat
systemctl enable --now sysstat
systemctl start sysstat

# Configure python-pip
cp /usr/bin/pip3 /usr/bin/pip

# Install python modules.
cat <<EOF > requirements.txt
kubernetes
docker
oyaml~=1.0
requests
ruamel.yaml~=0.17.21
EOF

pip install -r requirements.txt

az login
