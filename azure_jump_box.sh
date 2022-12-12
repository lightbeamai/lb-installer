#!/usr/bin/env bash

sudo apt-get update
sudo apt-get install unzip

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version

wget https://get.helm.sh/helm-v3.3.4-linux-amd64.tar.gz
tar -xvf helm-v3.3.4-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/

sudo curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
