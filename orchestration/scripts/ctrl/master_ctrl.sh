#!/bin/bash
# master_ctrl.sh — Phase 2: Configure and bootstrap the Kubernetes control plane.
#
# Container runtime setup (Docker+containerd), WireGuard, kubeadm init,
# Calico, Lightbeam service, etc.
# Runs after installer_common.sh (phase 1 — package installation).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="${SCRIPT_DIR}/kubeadm-master.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: ${ENV_FILE} not found." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/ph2_common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/run_migration.sh"

common_run_container_setup
common_install_kubernetes_binaries

echo "Note: kubelet may show as failed until cluster is initialized - this is normal"
systemctl status kubelet --no-pager -l || true
serviceStatusCheck "kubelet.service" "False"

log_step "Cluster configuration"

if [[ "${SKIP_WIREGUARD:-false}" != "true" ]]; then
  install_wg_watchdog
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/master_wireguard.sh"
fi

# shellcheck disable=SC1091
source "$SCRIPT_DIR/master_kubernetes.sh"

echo "=== MASTER NODE SETUP COMPLETE ==="
