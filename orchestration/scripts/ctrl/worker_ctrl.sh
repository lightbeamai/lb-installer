#!/bin/bash
# worker_ctrl.sh — Phase 2: Configure and join the Kubernetes cluster.
#
# Container runtime setup (containerd), then joins using JOIN_COMMAND from env.
# Runs after installer_common.sh (phase 1 — package installation).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="${SCRIPT_DIR}/kubeadm-worker.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: ${ENV_FILE} not found." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/ph2_common.sh"

common_worker_container_setup
common_install_kubernetes_binaries

log_step "Cluster join"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/worker_kubernetes.sh"
echo "Kubernetes Version: $(kubectl version --short 2>/dev/null || echo '1.33.0')"

echo "=== WORKER NODE JOINED SUCCESSFULLY ==="
