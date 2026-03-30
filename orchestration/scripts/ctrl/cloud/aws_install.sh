#!/bin/bash
# aws_install.sh — Install AWS CLI if not already present.
#
# Sourced by aws_token.sh at load time so that the CLI is guaranteed to be
# available before any token store operations are attempted.

set -euo pipefail

ensure_aws_cli() {
  if command -v aws >/dev/null 2>&1; then
    return 0
  fi

  echo "AWS CLI not found. Installing awscli..."
  source /etc/os-release
  local os_id="${ID:-}"
  local os_like="${ID_LIKE:-}"

  install_aws_cli_v2() {
    local tmpdir=""
    tmpdir="$(mktemp -d /tmp/awscli-install.XXXXXX)"

    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "${tmpdir}/awscliv2.zip"
    elif command -v wget >/dev/null 2>&1; then
      wget -qO "${tmpdir}/awscliv2.zip" "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    else
      echo "ERROR: curl/wget missing; cannot download AWS CLI v2 installer" >&2
      rm -rf "$tmpdir"
      return 1
    fi

    if ! command -v unzip >/dev/null 2>&1; then
      if [[ "$os_id" == "ubuntu" || "$os_id" == "debian" || "$os_like" == *"debian"* ]]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y || true
        apt-get install -y unzip || true
      elif [[ "$os_id" == "rhel" || "$os_like" == *"rhel"* || "$os_like" == *"fedora"* ]]; then
        dnf install -y unzip || yum install -y unzip || true
      fi
    fi

    if ! command -v unzip >/dev/null 2>&1; then
      echo "ERROR: unzip missing; cannot install AWS CLI v2" >&2
      rm -rf "$tmpdir"
      return 1
    fi

    ( cd "$tmpdir" && unzip -q awscliv2.zip && ./aws/install --update >/dev/null 2>&1 || ./aws/install >/dev/null 2>&1 ) || {
      rm -rf "$tmpdir"
      return 1
    }
    rm -rf "$tmpdir"
    return 0
  }

  if [[ "$os_id" == "ubuntu" || "$os_id" == "debian" || "$os_like" == *"debian"* ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y || true
    if ! apt-get install -y awscli >/dev/null 2>&1; then
      echo "apt awscli package unavailable; falling back to AWS CLI v2 installer..."
      apt-get install -y curl unzip >/dev/null 2>&1 || true
      install_aws_cli_v2 || true
    fi
  elif [[ "$os_id" == "rhel" || "$os_like" == *"rhel"* || "$os_like" == *"fedora"* ]]; then
    if ! (dnf install -y awscli >/dev/null 2>&1 || yum install -y awscli >/dev/null 2>&1); then
      echo "yum/dnf awscli package unavailable; falling back to AWS CLI v2 installer..."
      dnf install -y curl unzip >/dev/null 2>&1 || yum install -y curl unzip >/dev/null 2>&1 || true
      install_aws_cli_v2 || true
    fi
  else
    echo "ERROR: Unsupported OS for awscli installation. ID=$os_id ID_LIKE=$os_like" >&2
    return 1
  fi

  if ! command -v aws >/dev/null 2>&1; then
    echo "ERROR: awscli installation completed but 'aws' is still unavailable" >&2
    return 1
  fi
}

# Install upfront so all subsequent token operations can rely on the CLI.
ensure_aws_cli
