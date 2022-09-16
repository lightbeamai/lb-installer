#!/usr/bin/bash

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
