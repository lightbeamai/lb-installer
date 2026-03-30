#!/bin/bash
# master_wireguard.sh — Configure the WireGuard VPN server on the control-plane node.
#
# Sourced by master_ctrl.sh.

set -euo pipefail

PRIMARY_IFACE=$(ip route show default | awk '{print $5; exit}')

log_step "Configure WireGuard"
mkdir -p /etc/wireguard
WG_SERVER_CONF="${SCRIPT_DIR}/wg-server.conf"
if [[ ! -f "$WG_SERVER_CONF" ]]; then
  echo "ERROR: Missing ${WG_SERVER_CONF}"
  exit 1
fi
cp "$WG_SERVER_CONF" /etc/wireguard/wg0.conf
sed -i 's/\<sudo[[:space:]]\+//g' /etc/wireguard/wg0.conf
if [[ -n "${PRIMARY_IFACE:-}" ]]; then
  sed -i -E "s/-o[[:space:]]+ens[0-9]+/-o ${PRIMARY_IFACE}/g" /etc/wireguard/wg0.conf
fi
if grep -q '^MTU = ' /etc/wireguard/wg0.conf; then
  sed -i 's/^MTU = .*/MTU = 1280/' /etc/wireguard/wg0.conf
else
  sed -i '/^\[Interface\]/a MTU = 1280' /etc/wireguard/wg0.conf
fi
chmod 600 /etc/wireguard/wg0.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
if [[ ! -f /usr/lib/systemd/system/wg-quick@.service && ! -f /lib/systemd/system/wg-quick@.service ]]; then
  echo "ERROR: wg-quick@.service not found after dependency installation"
  exit 1
fi
systemctl enable --now wg-quick@wg0
