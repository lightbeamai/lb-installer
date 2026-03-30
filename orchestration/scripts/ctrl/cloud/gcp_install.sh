#!/bin/bash
# gcp_install.sh — Ensure python3 is available on the node.
#
# Sourced by gcp_token.sh at load time so that python3 is guaranteed to be
# present before any token store operations (which use inline Python) run.

set -euo pipefail

ensure_python3() {
  if command -v python3 >/dev/null 2>&1; then
    return 0
  fi

  echo "python3 not found. Installing..."
  source /etc/os-release
  local os_id="${ID:-}"
  local os_like="${ID_LIKE:-}"

  if [[ "$os_id" == "ubuntu" || "$os_id" == "debian" || "$os_like" == *"debian"* ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y || true
    apt-get install -y python3 || true
  elif [[ "$os_id" == "rhel" || "$os_like" == *"rhel"* || "$os_like" == *"fedora"* ]]; then
    dnf install -y python3 >/dev/null 2>&1 || yum install -y python3 >/dev/null 2>&1 || true
  else
    echo "ERROR: Unsupported OS for python3 installation. ID=$os_id ID_LIKE=$os_like" >&2
    return 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 installation completed but 'python3' is still unavailable" >&2
    return 1
  fi
}

# Install upfront so all subsequent token operations can rely on python3.
ensure_python3
