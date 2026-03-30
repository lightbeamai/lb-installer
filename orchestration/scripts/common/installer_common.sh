#!/bin/bash
# installer_common.sh — Phase 1: Package installation for all node types.
#
# Single entry point for master, ctrl worker, and edge worker phase 1.
# Sources packages.sh (OS detection + downloads) then ph1_common.sh (package install + bashrc).
set -euo pipefail

# Force IPv4 for apt — private-subnet instances may not have IPv6 routes,
# and IPv6 attempts cause long timeouts before falling back to IPv4.
echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/packages.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/ph1_common.sh"

echo "✓ All packages installed."
