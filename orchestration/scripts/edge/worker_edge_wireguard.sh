#!/bin/bash
# worker_edge_wireguard.sh — WireGuard + udp2raw setup and VPN validation for edge nodes.
#
# Sourced by worker_edge.sh. Expects env vars from edge-config.env and
# functions from ph2_common.sh to be loaded.

set -euo pipefail

VPN_WAIT_SECONDS=300
VPN_POLL_SECONDS=10

print_wireguard_failure_diagnostics() {
  echo "WireGuard startup diagnostics:"
  systemctl status wg-quick@wg0 --no-pager || true
  journalctl -xeu wg-quick@wg0.service --no-pager || true
  echo "Rendered /etc/wireguard/wg0.conf (private key redacted):"
  sed -E 's/^(PrivateKey = ).*/\1<redacted>/' /etc/wireguard/wg0.conf || true
}

wait_for_udp2raw_ready() {
  local elapsed=0
  local endpoint_host="${WIREGUARD_ENDPOINT%:*}"
  local endpoint_port="${WIREGUARD_ENDPOINT##*:}"
  local tcp_failures=0

  echo "Waiting for udp2raw tunnel readiness..."
  while (( elapsed < 90 )); do
    if timeout 5 bash -c "cat </dev/null >/dev/tcp/${endpoint_host}/${endpoint_port}" 2>/dev/null; then
      tcp_failures=0
    else
      tcp_failures=$((tcp_failures + 1))
      echo "TCP endpoint check failed for ${endpoint_host}:${endpoint_port} (${tcp_failures} consecutive failures)"
    fi

    if systemctl is-active --quiet udp2raw; then
      if journalctl -u udp2raw --no-pager -n 100 2>/dev/null | grep -q 'client_ready'; then
        echo "✓ udp2raw tunnel is ready"
        return 0
      fi

      if journalctl -u udp2raw --no-pager -n 120 2>/dev/null | grep -q 'state back to client_idle from client_tcp_handshake'; then
        if (( tcp_failures >= 3 )); then
          echo "ERROR: udp2raw cannot establish TCP handshake to ${endpoint_host}:${endpoint_port}"
          echo "Likely causes: control-plane udp2raw not running, TCP 51821 not listening, or firewall/network block."
          systemctl status udp2raw --no-pager || true
          journalctl -u udp2raw --no-pager -n 120 || true
          return 1
        fi
      fi
    fi

    echo "udp2raw tunnel not ready yet (${elapsed}s elapsed)..."
    sleep 5
    elapsed=$((elapsed + 5))
  done

  echo "ERROR: Timed out waiting for udp2raw tunnel readiness"
  systemctl status udp2raw --no-pager || true
  journalctl -xeu udp2raw.service --no-pager || true
  return 1
}

ensure_wireguard_up() {
  echo "Starting WireGuard service..."
  systemctl enable wg-quick@wg0
  systemctl restart wg-quick@wg0
  systemctl start wg-quick@wg0 || true
  systemctl status wg-quick@wg0 --no-pager || true
  wg show || true

  if systemctl is-active --quiet wg-quick@wg0; then
    echo "✓ WireGuard service is active"
    return 0
  fi

  echo "ERROR: WireGuard service failed to start"
  print_wireguard_failure_diagnostics
  return 1
}

wait_for_vpn() {
  log_step "Validate VPN Tunnel"
  echo "Waiting for WireGuard VPN handshake..."
  local elapsed=0
  local handshake_count=0
  while (( elapsed < VPN_WAIT_SECONDS )); do
    if ip addr show wg0 >/dev/null 2>&1; then
      echo "Validation: wg0 interface exists"
      handshake_count=$(wg show wg0 latest-handshakes 2>/dev/null | awk '$2 > 0 {count++} END {print count+0}')
      if [[ "$handshake_count" =~ ^[0-9]+$ ]] && (( handshake_count > 0 )); then
        echo "✓ WireGuard handshake detected"
        echo "Validation: VPN tunnel is up and passing peer handshakes"
        wg show || true
        return 0
      fi
    fi

    echo "VPN not ready yet (${elapsed}s elapsed)..."
    sleep "$VPN_POLL_SECONDS"
    elapsed=$((elapsed + VPN_POLL_SECONDS))
  done

  echo "ERROR: Timed out waiting for WireGuard VPN handshake"
  wg show || true
  return 1
}

wireguard_api_candidates() {
  local candidate=""
  local seen=""
  for candidate in "${WIREGUARD_CONTROL_PLANE_IP:-}" "10.8.0.1" "10.8.0.2"; do
    [[ -z "$candidate" ]] && continue
    if [[ " ${seen} " != *" ${candidate} "* ]]; then
      printf '%s\n' "$candidate"
      seen="${seen} ${candidate}"
    fi
  done
}

wait_for_api_healthz() {
  log_step "Validate Kubernetes API Over VPN"
  echo "Waiting for Kubernetes API health check over WireGuard..."
  local elapsed=0
  local candidate=""
  local endpoint=""
  local tried_endpoints=""
  tried_endpoints="$(wireguard_api_candidates | paste -sd ', ' -)"
  echo "API endpoint candidates: ${tried_endpoints}"
  while (( elapsed < 120 )); do
    while IFS= read -r candidate; do
      [[ -z "$candidate" ]] && continue
      endpoint="https://${candidate}:6443/healthz"
      if curl -k --connect-timeout 5 "$endpoint" >/tmp/edge-api-healthz 2>/dev/null; then
        if grep -qx 'ok' /tmp/edge-api-healthz; then
          WIREGUARD_CONTROL_PLANE_IP="$candidate"
          echo "✓ Kubernetes API reachable over VPN at ${endpoint}"
          rm -f /tmp/edge-api-healthz
          return 0
        fi
      fi
    done < <(wireguard_api_candidates)

    echo "API not reachable over VPN yet (${elapsed}s elapsed)..."
    sleep 5
    elapsed=$((elapsed + 5))
  done

  echo "ERROR: Timed out waiting for Kubernetes API over WireGuard."
  echo "Tried endpoints: ${tried_endpoints}"
  echo "WireGuard status for diagnostics:"
  wg show || true
  ip route get 10.8.0.1 2>/dev/null || true
  ip route get 10.8.0.2 2>/dev/null || true
  rm -f /tmp/edge-api-healthz
  return 1
}

# --- Execute ---

log_step "Install udp2raw"
if command -v udp2raw >/dev/null 2>&1; then
  echo "✓ udp2raw already installed"
else
  install -m 0755 /tmp/udp2raw_amd64 /usr/local/bin/udp2raw
  rm -f /tmp/udp2raw_binaries.tar.gz /tmp/udp2raw_amd64
  echo "✓ udp2raw installed"
fi
require_binary udp2raw

log_step "Configure WireGuard and udp2raw"
echo "Writing WireGuard and udp2raw configuration..."
mkdir -p /etc/wireguard
cat > /etc/wireguard/wg0.conf <<EOF_WG
[Interface]
PrivateKey = ${WIREGUARD_PRIVATE_KEY}
Address = ${WIREGUARD_ADDRESS}
MTU = 1280

[Peer]
PublicKey = ${WIREGUARD_PEER_PUBLIC_KEY}
AllowedIPs = ${WIREGUARD_ALLOWED_IPS}
Endpoint = 127.0.0.1:51820
PersistentKeepalive = 25
EOF_WG
sed -i 's/\<sudo[[:space:]]\+//g' /etc/wireguard/wg0.conf
if grep -q '^MTU = ' /etc/wireguard/wg0.conf; then
  sed -i 's/^MTU = .*/MTU = 1280/' /etc/wireguard/wg0.conf
else
  sed -i '/^\[Interface\]/a MTU = 1280' /etc/wireguard/wg0.conf
fi
chmod 600 /etc/wireguard/wg0.conf
ensure_wireguard_up

echo "Configuring TCP fallback tunnel to ${WIREGUARD_ENDPOINT} via udp2raw..."
cat > /etc/udp2raw.conf <<EOF_UDPRAW
-c
-l 127.0.0.1:51820
-r ${WIREGUARD_ENDPOINT}
-k "${UDP2RAW_PASSWORD}"
--raw-mode faketcp
-a
EOF_UDPRAW
chmod 600 /etc/udp2raw.conf

cat > /etc/systemd/system/udp2raw.service <<'EOF_SERVICE'
[Unit]
Description=udp2raw service
ConditionFileIsExecutable=/usr/local/bin/udp2raw
ConditionPathExists=/etc/udp2raw.conf
After=network.target

[Service]
Type=simple
User=root
Group=root
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
ExecStart=/usr/local/bin/udp2raw --conf-file /etc/udp2raw.conf
Restart=on-failure
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF_SERVICE

systemctl daemon-reload
echo "Starting udp2raw service..."
systemctl enable udp2raw
systemctl start udp2raw
echo "udp2raw tunnel process started; local endpoint is 127.0.0.1:51820"
wait_for_udp2raw_ready
echo "WireGuard is attempting VPN connection through udp2raw TCP fallback"

if ! systemctl is-active --quiet udp2raw; then
  echo "ERROR: udp2raw service failed to start"
  exit 1
fi

echo "Validating VPN interface..."
if ! ip addr show wg0 >/dev/null 2>&1; then
  echo "ERROR: wg0 interface was not created"
  exit 1
fi

echo "Checking WireGuard peer status..."
wg show || true
wait_for_vpn
wait_for_api_healthz

echo "✓ udp2raw tunnel established"
echo "✓ WireGuard interface started"
echo "✓ VPN connection path configured: wg0 -> udp2raw -> ${WIREGUARD_ENDPOINT}"
echo "✓ Kubernetes API reachable over VPN"
echo ""
