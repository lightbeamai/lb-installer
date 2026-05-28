#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_PATH="${LB_KUBELET_CONFIG_PATH:-/var/lib/kubelet/config.yaml}"

usage() {
  cat <<'EOF'
Usage: ./scripts/verify-kubelet-node-protection.sh

Verifies local kubelet node protection settings in /var/lib/kubelet/config.yaml.
If kubectl is available and can reach the cluster, it also prints this node's
Capacity, Allocatable, and pressure conditions.

Optional:
  LB_KUBELET_CONFIG_PATH=/path/to/config.yaml
  LB_NODE_NAME=<kubernetes-node-name>
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

warn() {
  echo "WARN: $*" >&2
}

ensure_python_yaml() {
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    return
  fi

  die "python3 with PyYAML is required for YAML verification. On Ubuntu, install it with: sudo apt-get install -y python3-yaml"
}

verify_local_config() {
  python3 - "$CONFIG_PATH" <<'PY'
import sys
import yaml

path = sys.argv[1]
required_maps = {
    "kubeReserved": ["cpu", "memory", "ephemeral-storage", "pid"],
    "systemReserved": ["cpu", "memory", "ephemeral-storage", "pid"],
    "evictionHard": [
        "memory.available",
        "nodefs.available",
        "nodefs.inodesFree",
        "imagefs.available",
        "imagefs.inodesFree",
    ],
    "evictionMinimumReclaim": [
        "memory.available",
        "nodefs.available",
        "imagefs.available",
    ],
}
fields = [
    "cgroupDriver",
    "kubeReserved",
    "systemReserved",
    "evictionHard",
    "evictionMinimumReclaim",
    "mergeDefaultEvictionSettings",
    "enforceNodeAllocatable",
]


def is_empty_or_zero(value):
    if value is None:
        return True
    text = str(value).strip()
    return text in {"", "0", "0%", "0Mi", "0Gi", "0m"}


with open(path, "r", encoding="utf-8") as handle:
    config = yaml.safe_load(handle) or {}

if not isinstance(config, dict):
    raise SystemExit(f"{path} is not a YAML mapping")

print("=== Local kubelet node protection config ===")
print(yaml.safe_dump({field: config.get(field) for field in fields}, default_flow_style=False, sort_keys=False).rstrip())

errors = []
if config.get("cgroupDriver") != "systemd":
    errors.append("cgroupDriver must be systemd")

if config.get("mergeDefaultEvictionSettings") is not True:
    errors.append("mergeDefaultEvictionSettings must be true")

enforce = config.get("enforceNodeAllocatable")
if not isinstance(enforce, list) or "pods" not in enforce:
    errors.append('enforceNodeAllocatable must include "pods"')

for map_name, keys in required_maps.items():
    value = config.get(map_name)
    if not isinstance(value, dict):
        errors.append(f"{map_name} must be a mapping")
        continue
    for key in keys:
        if key not in value:
            errors.append(f"{map_name}.{key} is missing")
        elif is_empty_or_zero(value[key]):
            errors.append(f"{map_name}.{key} has an unsafe empty or zero value")

if errors:
    print("=== Verification failures ===", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    raise SystemExit(1)
PY
}

verify_kubelet_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "systemctl is not available; skipped kubelet service check."
    return
  fi

  if systemctl is-active --quiet kubelet; then
    echo "kubelet service: active"
  else
    systemctl status kubelet --no-pager -l || true
    die "kubelet service is not active."
  fi
}

resolve_node_name() {
  if [ -n "${LB_NODE_NAME:-}" ]; then
    printf '%s\n' "$LB_NODE_NAME"
    return
  fi

  local candidates=()
  candidates+=("$(hostname -s 2>/dev/null || true)")
  candidates+=("$(hostname -f 2>/dev/null || true)")
  candidates+=("$(hostname 2>/dev/null || true)")

  local candidate
  for candidate in "${candidates[@]}"; do
    if [ -n "$candidate" ] && kubectl get node "$candidate" --request-timeout=5s >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  return 1
}

print_kubectl_details() {
  if ! command -v kubectl >/dev/null 2>&1; then
    warn "kubectl is not available; skipped cluster checks."
    return
  fi

  local node_name
  if ! node_name="$(resolve_node_name)"; then
    warn "kubectl is available, but this node name could not be resolved. Set LB_NODE_NAME to print cluster details."
    return
  fi

  echo "=== kubectl get node $node_name -o wide ==="
  kubectl get node "$node_name" -o wide

  echo "=== Node Capacity, Allocatable, and Conditions ==="
  local node_json
  node_json="$(mktemp)"
  kubectl get node "$node_name" -o json > "$node_json"
  python3 - "$node_json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    node = json.load(handle)
status = node.get("status", {})

for section in ("capacity", "allocatable"):
    values = status.get(section, {})
    print(section.capitalize() + ":")
    for key in ("cpu", "memory", "ephemeral-storage"):
        print(f"  {key}: {values.get(key, '<missing>')}")

print("Conditions:")
for condition in status.get("conditions", []):
    if condition.get("type") in {"Ready", "MemoryPressure", "DiskPressure", "PIDPressure"}:
        print(
            f"  {condition.get('type')}: {condition.get('status')} "
            f"reason={condition.get('reason', '')} message={condition.get('message', '')}"
        )
PY
  rm -f "$node_json"
}

main() {
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
  fi

  [ -f "$CONFIG_PATH" ] || die "Kubelet config not found at $CONFIG_PATH."
  ensure_python_yaml
  verify_local_config
  verify_kubelet_service
  print_kubectl_details

  echo "Kubelet node protection verification passed."
}

main "$@"
