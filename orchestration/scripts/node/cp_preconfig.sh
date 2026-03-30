#!/bin/bash
# Expects:
#   GATEWAY_IP       — public IP of the gateway node
#   CP_CONF_B64      — base64-encoded WireGuard client config for the control plane
#   WG_CLIENTS_B64   — base64-encoded newline-delimited "filename|b64_content" pairs
#                      for all WireGuard client configs (CP + workers)
set -euo pipefail

BOOTSTRAP_DIR="${REMOTE_BOOTSTRAP_DIR:-/var/lib/lightbeam/bootstrap}"

echo "${GATEWAY_IP}" > "${BOOTSTRAP_DIR}/gateway_ip"
mkdir -p "${BOOTSTRAP_DIR}/wg-clients"

printf '%s' "${WG_CLIENTS_B64}" | base64 -d | while IFS='|' read -r filename b64; do
    [ -z "${filename}" ] && continue
    printf '%s' "${b64}" | base64 -d > "${BOOTSTRAP_DIR}/wg-clients/${filename}"
done

printf '%s' "${CP_CONF_B64}" | base64 -d > "${BOOTSTRAP_DIR}/wg_server_conf"

echo PRECONFIG_DONE
