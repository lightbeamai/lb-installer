#!/bin/bash
# worker_kubernetes.sh — Join the Kubernetes cluster using JOIN_COMMAND from env.
#
# Sourced by worker_ctrl.sh. Expects JOIN_COMMAND to be set in the
# environment (written to kubeadm-worker.env in the bootstrap dir by the orchestrator).

set -euo pipefail

if [[ -z "${JOIN_COMMAND:-}" ]]; then
  echo "ERROR: JOIN_COMMAND not set. Check kubeadm-worker.env in bootstrap dir." >&2
  exit 1
fi

echo "Join command: $JOIN_COMMAND"

log_step "Join Kubernetes cluster"
if [[ -f /etc/kubernetes/kubelet.conf ]]; then
  echo "Stale kubeadm state detected; running kubeadm reset before join..."
  kubeadm reset -f
fi
eval "$JOIN_COMMAND"
