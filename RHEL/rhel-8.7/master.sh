#!/usr/bin/env bash

echo "1. Install and configure docker."
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
dnf install https://download.docker.com/linux/centos/7/x86_64/stable/Packages/containerd.io-1.2.6-3.3.el7.x86_64.rpm
dnf install docker-ce --allowerasing
systemctl enable docker
systemctl start docker
systemctl status docker

# Configure docker cgroup driver.
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

echo "2. Install kubernetes packages."
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

dnf install -y kubelet-1.23.0-0.x86_64 kubeadm-1.23.0-0.x86_64 kubectl-1.23.0-0.x86_64
systemctl enable kubelet
systemctl start kubelet
systemctl status kubelet

echo "3. Update system configuration."
sudo sysctl --system
setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables

# Disable Swap Permanently.
swapoff -a                 # Disable all devices marked as swap in /etc/fstab.
sed -e '/swap/ s/^#*/#/' -i /etc/fstab   # Comment the correct mounting point.
systemctl mask swap.target               # Completely disabled.

sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
systemctl disable firewalld
systemctl status firewalld

echo "4. Initialize kubernetes cluster:"
kubeadm init --pod-network-cidr=192.168.0.0/16
rm -rf $HOME/.kube
mkdir -p $HOME/.kube && cp -i /etc/kubernetes/admin.conf $HOME/.kube/config && chown $(id -u):$(id -g) $HOME/.kube/config

echo "5. Install network driver:"
curl https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/calico.yaml -O && kubectl apply -f calico.yaml

echo "6. Remove NoSchedule taint from master:"
kubectl taint nodes $(kubectl get nodes --selector=node-role.kubernetes.io/control-plane | awk 'FNR==2{print $1}') node-role.kubernetes.io/master-

echo "3. Setup helm"
curl -L -O https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz && tar -xvf helm-v3.13.1-linux-amd64.tar.gz && mv linux-amd64/helm /usr/local/bin/ && rm -f helm-v3.13.1-linux-amd64.tar.gz
helm version

sudo yum install -y git
sudo cp /usr/bin/python3 /usr/bin/python
sudo cp /usr/bin/pip3 /usr/bin/pip

# Install python modules.
cat <<EOF > requirements.txt
kubernetes
docker
oyaml~=1.0
requests
ruamel.yaml~=0.17.21
EOF

pip install -r requirements.txt

echo "Done! Ready to deploy LightBeam Cluster!!"
