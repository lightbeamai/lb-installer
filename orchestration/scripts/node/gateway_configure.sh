#!/bin/bash
# gateway_configure.sh — Full gateway configuration: NAT → WireGuard → udp2raw → K8s NAT → Nginx.
#
# Expects in the bundle (SCRIPT_DIR):
#   wg-server.conf       — WireGuard server config
#   gateway-config.env   — CONTROL_PLANE_IP
#
# Runs after gateway_packages.sh (phase 1).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GATEWAY_CONFIG="${GATEWAY_CONFIG:-${SCRIPT_DIR}/gateway-config.env}"
if [[ ! -f "$GATEWAY_CONFIG" ]]; then
  echo "ERROR: ${GATEWAY_CONFIG} not found." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$GATEWAY_CONFIG"

if [[ -z "${CONTROL_PLANE_IP:-}" ]]; then
  echo "ERROR: CONTROL_PLANE_IP not set in ${GATEWAY_CONFIG}" >&2
  exit 1
fi

log() {
  printf '[gateway-configure] %s\n' "$*"
}

# ---------------------------------------------------------------------------
# Step 1: NAT (general internet access for private subnet)
# ---------------------------------------------------------------------------

log "STEP 1 (NAT): begin"

sysctl -w net.ipv4.ip_forward=1
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
DEFAULT_IFACE=$(ip route show default | awk '{print $5}')
iptables -P FORWARD ACCEPT
iptables -A FORWARD -i "$DEFAULT_IFACE" -o "$DEFAULT_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i "$DEFAULT_IFACE" -o "$DEFAULT_IFACE" -j ACCEPT
iptables -t nat -A POSTROUTING -o "$DEFAULT_IFACE" -j MASQUERADE
echo 'iptables-persistent iptables-persistent/autosave_v4 boolean true' | debconf-set-selections
echo 'iptables-persistent iptables-persistent/autosave_v6 boolean true' | debconf-set-selections
if ! command -v netfilter-persistent >/dev/null 2>&1; then
  log "STEP 1 (NAT): netfilter-persistent missing, installing..."
fi
netfilter-persistent save

log "STEP 1 (NAT): done"

# ---------------------------------------------------------------------------
# Step 2: WireGuard server
# ---------------------------------------------------------------------------

log "STEP 2 (WireGuard): begin"

WG_CONF="${SCRIPT_DIR}/wg-server.conf"
if [[ -f "$WG_CONF" ]]; then
  log "STEP 2: source=${WG_CONF} (from bundle)"
  cp "$WG_CONF" /etc/wireguard/wg0.conf
elif [[ -f /etc/wireguard/wg0.conf ]]; then
  log "STEP 2: source=/etc/wireguard/wg0.conf (existing file)"
else
  echo "ERROR: missing WireGuard server config (${WG_CONF} not found and /etc/wireguard/wg0.conf not found)"
  exit 1
fi

chmod 600 /etc/wireguard/wg0.conf
systemctl enable --now wg-quick@wg0

log "STEP 2 (WireGuard): done"

# ---------------------------------------------------------------------------
# Step 3: udp2raw server (TCP:51821 → localhost:51820 WireGuard)
# ---------------------------------------------------------------------------

log "STEP 3 (udp2raw): begin"


cat > /etc/udp2raw.conf <<EOF
-s
-l 0.0.0.0:51821
-r 127.0.0.1:51820
-k "lightbeam"
--raw-mode faketcp
-a
EOF
chmod 600 /etc/udp2raw.conf

cat > /etc/systemd/system/udp2raw.service <<'EOF'
[Unit]
Description=udp2raw service
ConditionFileIsExecutable=/usr/local/bin/udp2raw
ConditionPathExists=/etc/udp2raw.conf
After=network.target
[Service]
Type=simple
User=root
Group=root
PIDFile=/run/udp2raw.pid
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
ExecStart=/usr/local/bin/udp2raw --conf-file /etc/udp2raw.conf
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now udp2raw.service

log "STEP 3 (udp2raw): done"

# ---------------------------------------------------------------------------
# Step 4: K8s API NAT (edge 10.8.0.1:6443 → control plane private IP:6443)
# ---------------------------------------------------------------------------

log "STEP 4 (K8s API NAT): begin — forwarding 10.8.0.1:6443 → ${CONTROL_PLANE_IP}:6443"

iptables -t nat -A PREROUTING -i wg0 -d 10.8.0.1 -p tcp --dport 6443 -j DNAT --to-destination "${CONTROL_PLANE_IP}:6443"
iptables -A FORWARD -i wg0 -p tcp -d "${CONTROL_PLANE_IP}" --dport 6443 -j ACCEPT
iptables -A FORWARD -o wg0 -p tcp -s "${CONTROL_PLANE_IP}" --sport 6443 -j ACCEPT
netfilter-persistent save

log "STEP 4 (K8s API NAT): done"

# ---------------------------------------------------------------------------
# Step 5: Nginx (HTTP reverse proxy → worker-1:30080)
# ---------------------------------------------------------------------------

log "STEP 5 (Nginx): begin"

log "Configuring Nginx to proxy to control plane at ${CONTROL_PLANE_IP}:30080"
cat > /etc/nginx/sites-available/default <<NGINX_EOF
server {
    listen 80;
    location / {
        proxy_pass http://${CONTROL_PLANE_IP}:30080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGINX_EOF

timeout 30 nginx -t
if systemctl is-active --quiet nginx; then
  timeout 45 systemctl reload nginx
else
  timeout 45 systemctl restart nginx
fi

log "STEP 5 (Nginx): done"

echo GATEWAY_CONFIGURE_DONE
