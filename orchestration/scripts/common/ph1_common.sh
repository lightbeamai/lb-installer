#!/bin/bash
# common.sh — Phase 1 shared initialization for all node bootstrap scripts.
#
# Sources prepare.sh and bashrc.sh (helper functions), installs OS packages,
# sets up bashrc, and provides install_wg_watchdog.
#
# Sourced by master.sh, ctrl/worker.sh, and edge/worker.sh after packages.sh.

set -euo pipefail

_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# prepare.sh: logging utilities, container runtime setup, Kubernetes
# node configuration helpers.  Defines functions only (no side effects).
# shellcheck disable=SC1090
source "$_COMMON_DIR/prepare.sh"

# bashrc.sh: shared shell history settings (setup_common_bashrc).
# shellcheck disable=SC1090
source "$_COMMON_DIR/bashrc.sh"

install_wg_watchdog() {
  local script_dir="${SHARED_SCRIPT_DIR:-${_COMMON_DIR}}"
  local watchdog="${script_dir}/wireguard-watchdog.sh"
  if [[ ! -f "$watchdog" ]]; then
    echo "WARNING: wireguard-watchdog.sh not found at $watchdog; skipping."
    return 0
  fi
  echo "Installing WireGuard watchdog..."
  WATCHDOG_SOURCE="$watchdog" \
    WG_IFACE=wg0 \
    WATCHDOG_MODE=interface \
    WATCHDOG_INTERVAL=2m \
    bash "$watchdog" install || true
  echo "✓ WireGuard watchdog installed"
}

echo "=== Package installation ==="
echo "Removing old packages..."
remove_old_packages
echo "Installing common dependencies..."
install_common_dependencies
echo "Installing container runtime..."
install_container_runtime
echo "Installing Kubernetes packages..."
install_kubernetes_packages
echo "Holding installed packages..."
hold_installed_packages
echo "Installing iptables persistence..."
install_iptables_persistence

log_step "Install udp2raw"
if command -v udp2raw >/dev/null 2>&1; then
  echo "✓ udp2raw already installed"
elif [[ -f /tmp/udp2raw_amd64 ]]; then
  install -m 0755 /tmp/udp2raw_amd64 /usr/local/bin/udp2raw
  rm -f /tmp/udp2raw_binaries.tar.gz /tmp/udp2raw_amd64
  echo "✓ udp2raw installed"
else
  echo "Downloading udp2raw..."
  wget -q -O /tmp/udp2raw_binaries.tar.gz \
    https://github.com/wangyu-/udp2raw/releases/download/20230206.0/udp2raw_binaries.tar.gz
  tar -xf /tmp/udp2raw_binaries.tar.gz -C /tmp/
  install -m 0755 /tmp/udp2raw_amd64 /usr/local/bin/udp2raw
  rm -f /tmp/udp2raw_binaries.tar.gz /tmp/udp2raw_amd64
  echo "✓ udp2raw installed"
fi

log_step "Install Helm"
if command -v helm >/dev/null 2>&1; then
  echo "✓ Helm already installed"
else
  curl -L -O https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz \
    && tar -xvf helm-v3.13.1-linux-amd64.tar.gz \
    && mv linux-amd64/helm /usr/local/bin/ \
    && rm -rf helm-v3.13.1-linux-amd64.tar.gz linux-amd64
  echo "✓ Helm installed"
fi
helm version

log_step "Download Calico CNI manifest"
wget -q -O "${SCRIPT_DIR}/calico.yaml" \
  https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/calico.yaml
echo "✓ Calico manifest downloaded to ${SCRIPT_DIR}/calico.yaml"

echo "=== Package installation complete ==="

setup_common_bashrc
