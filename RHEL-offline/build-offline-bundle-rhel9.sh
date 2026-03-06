#!/usr/bin/env bash
# build-offline-bundle-rhel9.sh
# Run on an internet-connected minimal RHEL 9 (x86_64) machine to create
# an offline bundle for air-gapped installations.

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

BUNDLE_DIR="lb-offline-bundle-rhel9"
mkdir -p $BUNDLE_DIR/rpms $BUNDLE_DIR/helm $BUNDLE_DIR/manifests

# --- dnf-plugins-core (needed for config-manager + dnf download) ---
dnf install -y dnf-plugins-core

# --- Docker CE ---
dnf config-manager --add-repo=https://download.docker.com/linux/rhel/docker-ce.repo
dnf download --resolve --arch=x86_64 --destdir=$BUNDLE_DIR/rpms \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# --- Kubernetes v1.34 ---
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.34/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# Pre-import GPG key so dnf download doesn't prompt
rpm --import https://pkgs.k8s.io/core:/stable:/v1.34/rpm/repodata/repomd.xml.key

dnf download --resolve --arch=x86_64 --destdir=$BUNDLE_DIR/rpms --disableexcludes=kubernetes \
  kubelet kubeadm kubectl

# --- RHEL 9 base deps required by Docker/kubelet on minimal installs ---
# dnf download skips already-installed packages, so use dnf reinstall --downloadonly
# to force-download packages that are installed on the build machine but may be
# absent on the customer's minimal RHEL 9 system.
dnf reinstall -y --downloadonly --downloaddir=$BUNDLE_DIR/rpms \
  container-selinux iptables-nft nftables wget selinux-policy selinux-policy-targeted libnftnl iptables-libs

# --- Helm v3.13.1 (static binary) ---
curl -L https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz \
  -o $BUNDLE_DIR/helm/helm-v3.13.1-linux-amd64.tar.gz

# --- Calico v3.29.0 manifest ---
curl -L https://raw.githubusercontent.com/projectcalico/calico/v3.29.0/manifests/calico.yaml \
  -o $BUNDLE_DIR/manifests/calico.yaml

# --- Save GPG keys for offline import ---
curl -L https://download.docker.com/linux/rhel/gpg \
  -o $BUNDLE_DIR/rpms/docker-gpg.key
curl -L https://pkgs.k8s.io/core:/stable:/v1.34/rpm/repodata/repomd.xml.key \
  -o $BUNDLE_DIR/rpms/k8s-gpg.key

# --- Include the install script in the bundle ---
cp "$(dirname "$0")/install-offline-bundle-rhel9.sh" $BUNDLE_DIR

tar -czf lb-offline-bundle-rhel9.tar.gz $BUNDLE_DIR/
echo ""
echo "Done: lb-offline-bundle-rhel9.tar.gz"
echo ""
echo "Transfer this file to the air-gapped machine and run:"
echo "  tar -xzf lb-offline-bundle-rhel9.tar.gz"
echo "  bash master-offline.sh lb-offline-bundle-rhel9"
echo "  or"
echo "  bash worker-offline.sh lb-offline-bundle-rhel9"
