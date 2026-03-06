#!/usr/bin/env bash
# install-offline-bundle-rhel9.sh
# Run on the air-gapped RHEL 9 machine from inside the extracted bundle directory.

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Importing GPG keys..."
rpm --import "$SCRIPT_DIR/rpms/docker-gpg.key"
rpm --import "$SCRIPT_DIR/rpms/k8s-gpg.key"

echo "Installing RPM packages..."
dnf install -y --disablerepo='*' --skip-broken "$SCRIPT_DIR"/rpms/*.rpm

echo "Installing Helm..."
tar -xvf "$SCRIPT_DIR/helm/helm-v3.13.1-linux-amd64.tar.gz" -C /tmp
mv /tmp/linux-amd64/helm /usr/local/bin/helm
chmod +x /usr/local/bin/helm

grep -qxF 'export PATH="/usr/local/bin:$PATH"' /etc/profile.d/local-bin.sh 2>/dev/null || \
  echo 'export PATH="/usr/local/bin:$PATH"' > /etc/profile.d/local-bin.sh

export PATH="/usr/local/bin:$PATH"
helm version

echo ""
echo "Offline bundle installation complete."
echo "You can now run master.sh or worker.sh."
