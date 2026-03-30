#!/bin/bash
# packages.sh — OS-aware package installation dispatcher.
#
# Detects the host OS and sources the appropriate per-OS implementation
# from the sibling os/ directory (os/rhel.sh or os/ubuntu.sh).
#
# Sourced by master_common.sh and worker_common.sh.

set -euo pipefail

source /etc/os-release
_PKG_OS_ID="${ID:-}"
_PKG_OS_ID_LIKE="${ID_LIKE:-}"

_is_rhel() {
  [[ "$_PKG_OS_ID" == "rhel" || "$_PKG_OS_ID_LIKE" == *"rhel"* || "$_PKG_OS_ID_LIKE" == *"fedora"* ]]
}

_is_ubuntu() {
  [[ "$_PKG_OS_ID" == "ubuntu" || "$_PKG_OS_ID" == "debian" || "$_PKG_OS_ID_LIKE" == *"debian"* ]]
}

_unsupported_os() {
  echo "ERROR: Unsupported OS (ID=$_PKG_OS_ID ID_LIKE=$_PKG_OS_ID_LIKE)" >&2
  exit 1
}

_PACKAGES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if _is_rhel; then
  # shellcheck disable=SC1090
  source "$_PACKAGES_DIR/os/rhel.sh"
elif _is_ubuntu; then
  # shellcheck disable=SC1090
  source "$_PACKAGES_DIR/os/ubuntu.sh"
else
  _unsupported_os
fi

