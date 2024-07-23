#!/bin/bash

# Prompt for the new IP address
read -p "Enter the new IP address for the Kubernetes master node: " IP

# Stop kubelet and Docker services
echo "Stopping kubelet and Docker services..."
sudo systemctl stop kubelet
sudo systemctl stop docker

# Backup Kubernetes and kubelet directories
echo "Backing up Kubernetes and kubelet directories..."
sudo mv -f /etc/kubernetes /etc/kubernetes-backup
sudo mv -f /var/lib/kubelet /var/lib/kubelet-backup

# Create new Kubernetes directory and copy necessary certificates
echo "Creating new Kubernetes directory and copying necessary certificates..."
sudo mkdir -p /etc/kubernetes
sudo cp -r /etc/kubernetes-backup/pki /etc/kubernetes
sudo rm -rf /etc/kubernetes/pki/{apiserver.*,etcd/peer.*}

# Start Docker service
echo "Starting Docker service..."
sudo systemctl start docker

# Initialize the Kubernetes cluster with the new IP address
echo "Initializing Kubernetes cluster with the new IP address: $IP..."
sudo kubeadm init --control-plane-endpoint $IP --ignore-preflight-errors=DirAvailable--var-lib-etcd

# Set up kubeconfig for the admin user
echo "Setting up kubeconfig for the admin user..."
rm -rf $HOME/.kube
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Restart kubelet service
echo "Starting kubelet service..."
sudo systemctl start kubelet

echo "Re-IP process completed successfully."

echo "On worker node run kubeadm reset and then kubeadm join command ref https://blog.mwpreston.net/2021/08/03/how-to-re-ip-your-kubernetes-cluster/ " 
