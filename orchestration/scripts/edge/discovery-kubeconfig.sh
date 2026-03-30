#!/usr/bin/env bash
set -euo pipefail

extract_kubeadm_token_from_join_command() {
  local join_command="$1"
  printf '%s\n' "$join_command" | sed -nE 's/.*--token[[:space:]]+([^[:space:]]+).*/\1/p'
}

create_discovery_kubeconfig() {
  local control_plane_ip="$1"
  local token_value="$2"
  local control_plane_ca_cert="$3"
  local output_path="${4:-/root/discovery-kubeconfig.yaml}"

  if [[ -z "$control_plane_ip" ]]; then
    echo "ERROR: control_plane_ip is required" >&2
    return 1
  fi

  if [[ -z "$token_value" ]]; then
    echo "ERROR: token_value is required" >&2
    return 1
  fi

  if [[ -z "$control_plane_ca_cert" ]]; then
    echo "ERROR: control_plane_ca_cert is required" >&2
    return 1
  fi

  cat > "$output_path" <<EOF_DISCOVERY
apiVersion: v1
kind: Config
clusters:
- name: edge-cluster
  cluster:
    server: https://${control_plane_ip}:6443
    certificate-authority-data: ${control_plane_ca_cert}
contexts:
- name: edge-context
  context:
    cluster: edge-cluster
    user: kubeadm-bootstrap
current-context: edge-context
users:
- name: kubeadm-bootstrap
  user:
    token: ${token_value}
EOF_DISCOVERY

  chmod 600 "$output_path"
}

main() {
  local control_plane_ip=""
  local token_value=""
  local control_plane_ca_cert=""
  local join_command=""
  local output_path="/root/discovery-kubeconfig.yaml"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --control-plane-ip)
        control_plane_ip="${2:-}"
        shift 2
        ;;
      --token)
        token_value="${2:-}"
        shift 2
        ;;
      --ca-cert)
        control_plane_ca_cert="${2:-}"
        shift 2
        ;;
      --join-command)
        join_command="${2:-}"
        shift 2
        ;;
      --output)
        output_path="${2:-}"
        shift 2
        ;;
      *)
        echo "ERROR: Unknown argument: $1" >&2
        echo "Usage: $0 --control-plane-ip <ip> [--token <token> | --join-command <command>] --ca-cert <base64> [--output <path>]" >&2
        return 1
        ;;
    esac
  done

  if [[ -z "$token_value" && -n "$join_command" ]]; then
    token_value="$(extract_kubeadm_token_from_join_command "$join_command")"
  fi

  create_discovery_kubeconfig "$control_plane_ip" "$token_value" "$control_plane_ca_cert" "$output_path"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
