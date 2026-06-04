#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=Ubuntu/common/kubelet-node-protection.sh
source "$REPO_ROOT/Ubuntu/common/kubelet-node-protection.sh"

CONFIG_PATH="${LB_KUBELET_CONFIG_PATH:-/var/lib/kubelet/config.yaml}"
BACKUP_DIR="${LB_KUBELET_CONFIG_BACKUP_DIR:-/var/backups/lb-kubelet-node-protection}"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/apply-kubelet-node-protection.sh

Patches /var/lib/kubelet/config.yaml with Lightbeam kubelet node protection
settings, restarts kubelet, and optionally patches the kube-system/kubelet-config
ConfigMap when kubectl can reach the cluster.

Environment overrides:
  LB_KUBE_RESERVED_CPU
  LB_KUBE_RESERVED_MEMORY
  LB_KUBE_RESERVED_EPHEMERAL_STORAGE
  LB_KUBE_RESERVED_PID
  LB_SYSTEM_RESERVED_CPU
  LB_SYSTEM_RESERVED_MEMORY
  LB_SYSTEM_RESERVED_EPHEMERAL_STORAGE
  LB_SYSTEM_RESERVED_PID
  LB_EVICTION_MEMORY_AVAILABLE
  LB_EVICTION_NODEFS_AVAILABLE
  LB_EVICTION_NODEFS_INODES_FREE
  LB_EVICTION_IMAGEFS_AVAILABLE
  LB_EVICTION_IMAGEFS_INODES_FREE
  LB_EVICTION_RECLAIM_MEMORY_AVAILABLE
  LB_EVICTION_RECLAIM_NODEFS_AVAILABLE
  LB_EVICTION_RECLAIM_IMAGEFS_AVAILABLE
  LB_ENFORCE_NODE_ALLOCATABLE

Optional:
  LB_KUBELET_CONFIG_PATH=/path/to/config.yaml
  LB_KUBELET_CONFIG_BACKUP_DIR=/path/to/backups
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

warn() {
  echo "WARN: $*" >&2
}

ensure_root() {
  if [ "${EUID}" -ne 0 ]; then
    die "Please run as root."
  fi
}

ensure_python_yaml() {
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    return
  fi

  if command -v apt-get >/dev/null 2>&1 && [ -f /etc/debian_version ]; then
    echo "Installing python3-yaml for robust kubelet YAML editing..."
    apt-get update -y
    apt-get install -y python3-yaml
  fi

  if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import yaml' >/dev/null 2>&1; then
    die "python3 with PyYAML is required. On Ubuntu, install it with: apt-get install -y python3-yaml"
  fi
}

patch_kubelet_yaml_file() {
  local input_path=$1
  local output_path=$2
  local label=$3

  lb_export_kubelet_node_protection_env
  python3 - "$input_path" "$output_path" "$label" <<'PY'
import os
import sys
import yaml

input_path, output_path, label = sys.argv[1:4]

FIELDS = [
    "cgroupDriver",
    "kubeReserved",
    "systemReserved",
    "evictionHard",
    "evictionMinimumReclaim",
    "mergeDefaultEvictionSettings",
    "enforceNodeAllocatable",
]


def env(name, default):
    value = os.environ.get(name, default)
    if value is None or value == "":
        raise SystemExit(f"{name} must not be empty")
    return value


def env_list(name, default):
    raw = env(name, default)
    values = [item.strip() for item in raw.split(",") if item.strip()]
    if not values:
        raise SystemExit(f"{name} must include at least one value")
    return values


def relevant(config):
    return {field: config.get(field) for field in FIELDS}


with open(input_path, "r", encoding="utf-8") as handle:
    config = yaml.safe_load(handle) or {}

if not isinstance(config, dict):
    raise SystemExit(f"{input_path} is not a YAML mapping")

before = relevant(config)

config["cgroupDriver"] = "systemd"
config["kubeReserved"] = {
    "cpu": env("LB_KUBE_RESERVED_CPU", "300m"),
    "memory": env("LB_KUBE_RESERVED_MEMORY", "512Mi"),
    "ephemeral-storage": env("LB_KUBE_RESERVED_EPHEMERAL_STORAGE", "2Gi"),
    "pid": env("LB_KUBE_RESERVED_PID", "1000"),
}
config["systemReserved"] = {
    "cpu": env("LB_SYSTEM_RESERVED_CPU", "300m"),
    "memory": env("LB_SYSTEM_RESERVED_MEMORY", "512Mi"),
    "ephemeral-storage": env("LB_SYSTEM_RESERVED_EPHEMERAL_STORAGE", "2Gi"),
    "pid": env("LB_SYSTEM_RESERVED_PID", "1000"),
}
config["evictionHard"] = {
    "memory.available": env("LB_EVICTION_MEMORY_AVAILABLE", "500Mi"),
    "nodefs.available": env("LB_EVICTION_NODEFS_AVAILABLE", "10%"),
    "nodefs.inodesFree": env("LB_EVICTION_NODEFS_INODES_FREE", "5%"),
    "imagefs.available": env("LB_EVICTION_IMAGEFS_AVAILABLE", "15%"),
    "imagefs.inodesFree": env("LB_EVICTION_IMAGEFS_INODES_FREE", "5%"),
}
config["evictionMinimumReclaim"] = {
    "memory.available": env("LB_EVICTION_RECLAIM_MEMORY_AVAILABLE", "256Mi"),
    "nodefs.available": env("LB_EVICTION_RECLAIM_NODEFS_AVAILABLE", "1Gi"),
    "imagefs.available": env("LB_EVICTION_RECLAIM_IMAGEFS_AVAILABLE", "1Gi"),
}
config["mergeDefaultEvictionSettings"] = True
config["enforceNodeAllocatable"] = env_list("LB_ENFORCE_NODE_ALLOCATABLE", "pods")

with open(output_path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(config, handle, default_flow_style=False, sort_keys=False)

with open(output_path, "r", encoding="utf-8") as handle:
    yaml.safe_load(handle)

after = relevant(config)

print(f"=== {label}: before ===")
print(yaml.safe_dump(before, default_flow_style=False, sort_keys=False).rstrip())
print(f"=== {label}: after ===")
print(yaml.safe_dump(after, default_flow_style=False, sort_keys=False).rstrip())
PY
}

restart_kubelet() {
  echo "Restarting kubelet..."
  systemctl daemon-reload
  systemctl restart kubelet

  for _ in $(seq 1 60); do
    if systemctl is-active --quiet kubelet; then
      echo "kubelet is active."
      return
    fi
    sleep 2
  done

  systemctl status kubelet --no-pager -l || true
  die "kubelet did not become active after restart."
}

patch_kubelet_configmap_if_available() {
  if ! command -v kubectl >/dev/null 2>&1; then
    warn "kubectl is not available; skipped kube-system/kubelet-config ConfigMap patch."
    return
  fi

  if ! kubectl get configmap kubelet-config -n kube-system --request-timeout=10s >/dev/null 2>&1; then
    warn "kubectl cannot read kube-system/kubelet-config; skipped ConfigMap patch."
    return
  fi

  local cm_backup="$BACKUP_DIR/kubelet-config-configmap-$TIMESTAMP.yaml"
  local cm_json cm_current cm_patched cm_patch_json
  cm_json="$(mktemp)"
  cm_current="$(mktemp)"
  cm_patched="$(mktemp)"
  cm_patch_json="$(mktemp)"

  echo "Backing up kube-system/kubelet-config ConfigMap to $cm_backup"
  if ! kubectl get configmap kubelet-config -n kube-system -o yaml > "$cm_backup"; then
    warn "Failed to back up kubelet-config ConfigMap; skipped ConfigMap patch."
    rm -f "$cm_json" "$cm_current" "$cm_patched" "$cm_patch_json"
    return
  fi

  if ! kubectl get configmap kubelet-config -n kube-system -o json > "$cm_json"; then
    warn "Failed to read kubelet-config ConfigMap as JSON; skipped ConfigMap patch."
    rm -f "$cm_json" "$cm_current" "$cm_patched" "$cm_patch_json"
    return
  fi

  if ! python3 - "$cm_json" "$cm_current" <<'PY'; then
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    configmap = json.load(handle)

kubelet_config = configmap.get("data", {}).get("kubelet")
if not kubelet_config:
    raise SystemExit("ConfigMap data.kubelet is missing")

with open(sys.argv[2], "w", encoding="utf-8") as handle:
    handle.write(kubelet_config)
PY
    warn "kube-system/kubelet-config does not contain data.kubelet; skipped ConfigMap patch."
    rm -f "$cm_json" "$cm_current" "$cm_patched" "$cm_patch_json"
    return
  fi

  if ! patch_kubelet_yaml_file "$cm_current" "$cm_patched" "ConfigMap kubelet config"; then
    warn "Failed to patch kubelet-config ConfigMap data locally; skipped ConfigMap patch."
    rm -f "$cm_json" "$cm_current" "$cm_patched" "$cm_patch_json"
    return
  fi

  python3 - "$cm_patched" "$cm_patch_json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    kubelet_config = handle.read()

with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump({"data": {"kubelet": kubelet_config}}, handle)
PY

  if kubectl patch configmap kubelet-config -n kube-system --type merge --patch-file "$cm_patch_json" >/dev/null; then
    echo "Patched kube-system/kubelet-config for future joining nodes."
  else
    warn "Failed to patch kube-system/kubelet-config; local kubelet config remains updated."
  fi

  rm -f "$cm_json" "$cm_current" "$cm_patched" "$cm_patch_json"
}

main() {
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
  fi

  ensure_root
  ensure_python_yaml

  [ -f "$CONFIG_PATH" ] || die "Kubelet config not found at $CONFIG_PATH. Run this after kubeadm init/join creates the file."

  mkdir -p "$BACKUP_DIR"
  local backup_path="$BACKUP_DIR/config.yaml.$TIMESTAMP.bak"
  local tmp_config
  tmp_config="$(mktemp)"

  echo "Backing up $CONFIG_PATH to $backup_path"
  cp -a "$CONFIG_PATH" "$backup_path"

  patch_kubelet_yaml_file "$CONFIG_PATH" "$tmp_config" "Local kubelet config"
  chown --reference="$CONFIG_PATH" "$tmp_config"
  chmod --reference="$CONFIG_PATH" "$tmp_config"
  mv "$tmp_config" "$CONFIG_PATH"

  restart_kubelet
  patch_kubelet_configmap_if_available

  echo "Kubelet node protection applied."
}

main "$@"
