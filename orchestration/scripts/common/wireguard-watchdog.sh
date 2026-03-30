#!/bin/bash
set -euo pipefail

THIS_SCRIPT_SOURCE="${WATCHDOG_SOURCE:-${BASH_SOURCE[0]}}"
DESTINATION="${WATCHDOG_DEST:-/usr/local/bin/wireguard-watchdog.sh}"
ENV_FILE="${WATCHDOG_ENV_FILE:-/etc/wireguard/watchdog.env}"
WG_IFACE="${WG_IFACE:-wg0}"
WATCHDOG_MODE="${WATCHDOG_MODE:-peer}"
WATCHDOG_ENABLED="${WATCHDOG_ENABLED:-1}"
WATCHDOG_RETRIES="${WATCHDOG_RETRIES:-3}"
SLEEP_TIMER="${SLEEP_TIMER:-5}"
PING_COUNT="${PING_COUNT:-1}"
PING_TIMEOUT="${PING_TIMEOUT:-3}"
WATCHDOG_INTERVAL="${WATCHDOG_INTERVAL:-2m}"
WATCHDOG_PEERS="${WATCHDOG_PEERS:-}"
WIREGUARD_ADDRESS="${WIREGUARD_ADDRESS:-}"

install_watchdog() {
  install -d -m 755 "$(dirname "$DESTINATION")"
  cp "$THIS_SCRIPT_SOURCE" "$DESTINATION"
  chmod 755 "$DESTINATION"

  install -d -m 755 "$(dirname "$ENV_FILE")"
  cat > "$ENV_FILE" <<EOF
WG_IFACE=${WG_IFACE}
WATCHDOG_MODE=${WATCHDOG_MODE}
WATCHDOG_ENABLED=${WATCHDOG_ENABLED}
WATCHDOG_RETRIES=${WATCHDOG_RETRIES}
SLEEP_TIMER=${SLEEP_TIMER}
PING_COUNT=${PING_COUNT}
PING_TIMEOUT=${PING_TIMEOUT}
WATCHDOG_INTERVAL=${WATCHDOG_INTERVAL}
WATCHDOG_PEERS=${WATCHDOG_PEERS}
WIREGUARD_ADDRESS=${WIREGUARD_ADDRESS}
EOF

  cat > /etc/systemd/system/wireguard-watchdog.service <<EOF
[Unit]
Description=WireGuard watchdog
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash ${DESTINATION}
EOF

  cat > /etc/systemd/system/wireguard-watchdog.timer <<EOF
[Unit]
Description=Run WireGuard watchdog periodically

[Timer]
OnBootSec=${WATCHDOG_INTERVAL}
OnUnitActiveSec=${WATCHDOG_INTERVAL}
Unit=wireguard-watchdog.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now wireguard-watchdog.timer
}

load_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "[wg-watchdog] Missing config: $ENV_FILE" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  . "$ENV_FILE"

  WATCHDOG_MODE="${WATCHDOG_MODE:-peer}"
  WATCHDOG_ENABLED="${WATCHDOG_ENABLED:-1}"
  WATCHDOG_RETRIES="${WATCHDOG_RETRIES:-3}"
  SLEEP_TIMER="${SLEEP_TIMER:-5}"
  PING_COUNT="${PING_COUNT:-1}"
  PING_TIMEOUT="${PING_TIMEOUT:-3}"
  WG_IFACE="${WG_IFACE:-wg0}"
}

is_interface_healthy() {
  ip link show "$WG_IFACE" >/dev/null 2>&1 && systemctl is-active --quiet "wg-quick@${WG_IFACE}"
}

is_connection_up() {
  ping -q -c "$PING_COUNT" -W "$PING_TIMEOUT" "$1" >/dev/null 2>&1
}

check_connection() {
  local attempt=0
  while (( attempt <= WATCHDOG_RETRIES )); do
    if (( attempt > 0 )); then
      sleep "$SLEEP_TIMER"
    fi

    local peer
    for peer in ${WATCHDOG_PEERS}; do
      if is_connection_up "$peer"; then
        return 0
      fi
    done

    (( attempt++ ))
  done
  return 1
}

restart_connection() {
  if systemctl restart "wg-quick@${WG_IFACE}"; then
    if check_connection; then
      return 0
    fi
  fi
  return 1
}

run_watchdog() {
  load_env

  if [[ "$WATCHDOG_ENABLED" -ne 1 ]]; then
    logger -t wireguard-watchdog "watchdog disabled"
    exit 0
  fi

  if [[ "$WATCHDOG_MODE" == "interface" ]]; then
    if is_interface_healthy; then
      logger -t wireguard-watchdog "interface healthy"
      exit 0
    fi

    logger -t wireguard-watchdog "interface down; attempting restart"
    if systemctl restart "wg-quick@${WG_IFACE}"; then
      if is_interface_healthy; then
        logger -t wireguard-watchdog "interface restored"
        exit 0
      fi
    fi

    logger -t wireguard-watchdog "failed to restore interface"
    exit 1
  fi

  local peers_override="${WATCHDOG_PEERS:-}"
  local peers_list
  if [[ -n "$peers_override" ]]; then
    peers_list="$peers_override"
  elif [[ -n "${WIREGUARD_ADDRESS:-}" ]]; then
    peers_list="$WIREGUARD_ADDRESS"
  else
    logger -t wireguard-watchdog "no WATCHDOG_PEERS/WIREGUARD_ADDRESS configured"
    exit 1
  fi

  WATCHDOG_PEERS="$peers_list"

  if check_connection; then
    logger -t wireguard-watchdog "connection healthy"
    exit 0
  fi

  logger -t wireguard-watchdog "connection down; attempting restart"
  if restart_connection; then
    logger -t wireguard-watchdog "connection restored"
    exit 0
  fi

  logger -t wireguard-watchdog "failed to restore connection"
  exit 1
}

if [[ "${1:-}" == "install" ]]; then
  install_watchdog
  exit 0
fi

run_watchdog
