#!/bin/bash
# worker_edge.sh — Phase 2: Configure WireGuard VPN and join the Kubernetes cluster.
#
# Runs after installer_common.sh (phase 1 — package installation).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EDGE_CONFIG="${EDGE_CONFIG:-${SCRIPT_DIR}/edge-config.env}"
if [[ ! -f "$EDGE_CONFIG" ]]; then
  echo "ERROR: ${EDGE_CONFIG} not found. Run install.sh to provision credentials before running worker_edge.sh." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$EDGE_CONFIG"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/ph2_common.sh"

common_worker_container_setup
common_install_kubernetes_binaries
install_wg_watchdog

# shellcheck disable=SC1091
source "$SCRIPT_DIR/worker_edge_wireguard.sh"
# shellcheck disable=SC1091
log_step "Join the Kubernetes Cluster"
source "$SCRIPT_DIR/worker_edge_kubernetes.sh"
echo "✓ Worker joined the Kubernetes cluster"
echo "=== WORKER NODE JOINED SUCCESSFULLY ==="
