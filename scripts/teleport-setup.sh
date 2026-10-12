#!/bin/bash
set -euo pipefail

# Usage:
#   bash teleport-setup.sh [auth_token] [cluster_name]
#
#   Fresh install (no Teleport at ~/teleport): auth_token is required.
#     cluster_name is optional -- auto-detected from kubectl if omitted.
#   Existing install: upgrades the binary to TARGET_VERSION; arguments are ignored.

TARGET_VERSION="17.7.23"
PROXY_SERVER="${TELEPORT_PROXY:-teleport-internal.lightbeam-ai.com:443}"
# Explicit CA Pin to bypass local OS certificate store issues natively
CA_PIN="${TELEPORT_CA_PIN:-sha256:e08c84addee6376f9207972253be934cb7d02a39c022721b8d4f0ddbfd1c536f}"
AUTH_TOKEN="${1:-}"
OVERRIDE_CLUSTER="${2:-}"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*" >&2; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

case "$(uname -m)" in
  x86_64|amd64)  ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) error "Unsupported architecture: $(uname -m)" ;;
esac
ARCHIVE="teleport-v${TARGET_VERSION}-linux-${ARCH}-bin.tar.gz"
TELEPORT_URL="https://cdn.teleport.dev/${ARCHIVE}"

# ── Detect install path ───────────────────────────────────────────────────────
USER_HOME="$HOME"
RUN_AS_USER="$(id -un)"
RUN_AS_GROUP="$(id -gn)"
# Under `sudo bash teleport-setup.sh`, $HOME is usually /root. Install for the
# invoking user instead, unless Teleport already lives under root's home.
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  SUDO_HOME=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6 || true)
  if [ -n "$SUDO_HOME" ] && { [ -f "$SUDO_HOME/teleport/bin/teleport" ] || [ ! -f "$USER_HOME/teleport/bin/teleport" ]; }; then
    USER_HOME="$SUDO_HOME"
    RUN_AS_USER="$SUDO_USER"
    RUN_AS_GROUP="$(id -gn "$SUDO_USER")"
    info "Running via sudo -- installing for $RUN_AS_USER under $USER_HOME"
  fi
fi
REAL_PATH=$(eval echo "$USER_HOME")
INSTALL_DIR="$REAL_PATH/teleport"
BIN_DIR="$INSTALL_DIR/bin"
CONFIG_FILE="$INSTALL_DIR/config/teleport.yaml"
DATA_DIR="$INSTALL_DIR/data"
LOG_FILE="$INSTALL_DIR/teleport.log"

SERVICE_NAME="teleport"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LOG_OFFSET=0

USE_SYSTEMD=true
if ! command -v systemctl >/dev/null 2>&1 || [ ! -d /run/systemd/system ]; then
  USE_SYSTEMD=false
  warn "systemd not available on this host -- falling back to a supervised background process (not reboot-safe)."
fi

RUN_PRIV() {
  # Run a privileged command so this script works whether it's run as root
  # directly or as a regular user with sudo access.
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

SYSTEMCTL() {
  # Re-running is always safe (idempotent).
  RUN_PRIV systemctl "$@"
}

WRITE_UNIT_FILE() {
  # Regenerated every run so paths/user always match the current environment,
  # and so re-running this script after e.g. moving the install dir self-heals
  # the unit file rather than leaving it stale.
  local tmp_unit
  tmp_unit="$(mktemp)"
  cat > "$tmp_unit" <<UNIT
[Unit]
Description=Teleport SSH/K8s Access Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_AS_USER}
Group=${RUN_AS_GROUP}
ExecStart=${BIN_DIR}/teleport start --config=${CONFIG_FILE}
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=multi-user.target
UNIT

  if [ -f "$SERVICE_FILE" ] && cmp -s "$tmp_unit" "$SERVICE_FILE"; then
    info "systemd unit already up to date, no change needed."
    rm -f "$tmp_unit"
    return 0
  fi

  info "Installing/updating systemd unit at $SERVICE_FILE"
  RUN_PRIV cp "$tmp_unit" "$SERVICE_FILE"
  rm -f "$tmp_unit"
  SYSTEMCTL daemon-reload
}

SERVICE_IS_ACTIVE() {
  SYSTEMCTL is-active --quiet "$SERVICE_NAME" 2>/dev/null
}

FIND_MANUAL_PIDS() {
  # Any host-level "teleport start" process, however it was launched (absolute
  # path, ./teleport, via PATH, ...). Processes inside containers (e.g. a
  # teleport-kube-agent pod) and the systemd unit's own main PID are excluded.
  local main_pid=0 pid
  if [ "$USE_SYSTEMD" = true ]; then
    main_pid=$(SYSTEMCTL show -p MainPID --value "$SERVICE_NAME" 2>/dev/null || echo 0)
  fi
  for pid in $(pgrep -f '(^|/)teleport start( |$)' || true); do
    [ "$pid" = "$main_pid" ] && continue
    [ -d "/proc/$pid" ] || continue
    grep -qE 'kubepods|docker|containerd|libpod|crio' "/proc/$pid/cgroup" 2>/dev/null && continue
    echo "$pid"
  done
}

ALIVE_PIDS() {
  local pid
  for pid in "$@"; do
    ps -p "$pid" >/dev/null 2>&1 && echo "$pid"
  done
  return 0
}

KILL_MANUAL_PROCESS() {
  # Stops Teleport started outside systemd (e.g. via nohup by the previous
  # installer / start.sh helper) so it doesn't run alongside the systemd one.
  local running_pids alive pid i
  running_pids=$(FIND_MANUAL_PIDS)
  if [ -z "$running_pids" ]; then
    info "No manually started Teleport process found."
    RUN_PRIV rm -f "$INSTALL_DIR/teleport.pid"
    return 0
  fi

  for pid in $running_pids; do
    info "Stopping manually started Teleport process PID $pid (user: $(ps -o user= -p "$pid" 2>/dev/null | tr -d ' '), cmd: $(ps -o args= -p "$pid" 2>/dev/null))"
  done
  # Privileged kill: the process may belong to another user (e.g. started as root).
  # shellcheck disable=SC2086
  RUN_PRIV kill $running_pids 2>/dev/null || true

  # shellcheck disable=SC2086
  for i in $(seq 1 10); do
    alive=$(ALIVE_PIDS $running_pids)
    [ -z "$alive" ] && break
    sleep 1
  done

  if [ -n "$alive" ]; then
    warn "Teleport still running after 10s, sending SIGKILL (PID: $(echo $alive))"
    # shellcheck disable=SC2086
    RUN_PRIV kill -9 $alive 2>/dev/null || true
    sleep 1
    # shellcheck disable=SC2086
    alive=$(ALIVE_PIDS $alive)
    [ -n "$alive" ] && error "Could not stop Teleport process(es) (PID: $(echo $alive)). Stop them manually and re-run."
  fi
  RUN_PRIV rm -f "$INSTALL_DIR/teleport.pid"
}

FIX_OWNERSHIP() {
  # Files left behind by a Teleport previously run as another user (typically
  # root) would stop the service, which runs as $RUN_AS_USER, from replacing its
  # binary, reading its data dir or appending to its log.
  [ -d "$INSTALL_DIR" ] || return 0
  if [ -n "$(RUN_PRIV find "$INSTALL_DIR" ! -user "$RUN_AS_USER" -print -quit 2>/dev/null)" ]; then
    info "Fixing ownership of $INSTALL_DIR to ${RUN_AS_USER}:${RUN_AS_GROUP}"
    RUN_PRIV chown -R "${RUN_AS_USER}:${RUN_AS_GROUP}" "$INSTALL_DIR"
  fi
}

STOP_SERVICE() {
  if [ "$USE_SYSTEMD" = true ]; then
    if SYSTEMCTL is-enabled --quiet "$SERVICE_NAME" 2>/dev/null || [ -f "$SERVICE_FILE" ]; then
      if SERVICE_IS_ACTIVE; then
        info "Stopping Teleport (systemd)..."
        SYSTEMCTL stop "$SERVICE_NAME"
      else
        info "Teleport service already stopped."
      fi
    else
      info "No existing Teleport systemd service found."
    fi
  fi
  KILL_MANUAL_PROCESS
  FIX_OWNERSHIP
}

LOG_SIZE() {
  if [ -f "$LOG_FILE" ]; then
    wc -c < "$LOG_FILE" | tr -d ' '
  else
    echo 0
  fi
}

START_SERVICE() {
  if [ "$USE_SYSTEMD" = true ]; then
    KILL_MANUAL_PROCESS
  fi
  FIX_OWNERSHIP
  # The log is appended to across runs; only lines written after this point
  # count as evidence that the newly started Teleport connected.
  LOG_OFFSET=$(LOG_SIZE)

  if [ "$USE_SYSTEMD" = true ]; then
    info "Enabling Teleport to start on boot..."
    SYSTEMCTL enable "$SERVICE_NAME" >/dev/null
    info "Starting Teleport (systemd)..."
    SYSTEMCTL restart "$SERVICE_NAME"
  else
    mkdir -p "$(dirname "$LOG_FILE")"
    info "Starting Teleport as a background process (no systemd)..."
    nohup "${BIN_DIR}/teleport" start --config="${CONFIG_FILE}" >> "$LOG_FILE" 2>&1 &
    disown
    info "Started with PID $!. NOTE: this will NOT survive a reboot -- install systemd to fix that."
  fi
}

INSTALL_BINARY() {
  # Download (skip if archive already present), extract and swap in the binary.
  local archive_path="$BIN_DIR/$ARCHIVE"
  local extract_dir="$BIN_DIR/temp_extract"

  if [ -f "$archive_path" ]; then
    info "Archive for v${TARGET_VERSION} already present, skipping download."
  else
    info "Downloading Teleport v${TARGET_VERSION} (${ARCH})..."
    curl -fL -o "$archive_path" "$TELEPORT_URL" || { rm -f "$archive_path"; error "Failed to download Teleport v${TARGET_VERSION}."; }
  fi

  info "Extracting..."
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  tar -xzf "$archive_path" -C "$extract_dir"

  info "Installing new binary..."
  cp "$extract_dir/teleport/teleport" "$BIN_DIR/teleport.new"
  rm -rf "$extract_dir" "$archive_path"
  chmod +x "$BIN_DIR/teleport.new"
  mv -f "$BIN_DIR/teleport.new" "$BIN_DIR/teleport"
}

DETECT_CLUSTER_NAME() {
  if [ -n "$OVERRIDE_CLUSTER" ]; then
    echo "$OVERRIDE_CLUSTER"
    return
  fi

  info "Detecting cluster name from kubectl..."
  local name
  name=$(kubectl get cm lightbeam-api-gateway-configmap -o yaml 2>/dev/null \
    | grep "CUSTOMER_NAME" | awk '{print $2}' | tr -d '[:space:]' || true)

  if [ -n "$name" ]; then
    info "Detected cluster name: $name"
    echo "$name"
  else
    warn "Could not detect cluster name from configmap."
    read -rp "Enter cluster name manually: " name
    [ -z "$name" ] && error "Cluster name cannot be empty."
    echo "$name"
  fi
}

WRITE_CONFIG() {
  info "Writing Teleport config to $CONFIG_FILE"
  mkdir -p "$(dirname "$CONFIG_FILE")" "$DATA_DIR"
  local old_umask
  old_umask=$(umask)
  umask 077  # config contains the join token
  cat > "$CONFIG_FILE" <<CONFIG
version: v3
teleport:
  nodename: ${CLUSTER_NAME}
  data_dir: ${DATA_DIR}
  auth_token: ${AUTH_TOKEN}
  ca_pin: "${CA_PIN}"
  proxy_server: ${PROXY_SERVER}

ssh_service:
  enabled: yes
  labels:
    cluster: ${CLUSTER_NAME}
    env: production
    version: v3

auth_service:
  enabled: no

proxy_service:
  enabled: no
CONFIG
  umask "$old_umask"
}

# ── Pre-flight checks ─────────────────────────────────────────────────────────
info "Checking existing installation..."
FRESH_INSTALL=false
if [ ! -f "$BIN_DIR/teleport" ]; then
  FRESH_INSTALL=true
  info "No Teleport binary found at $BIN_DIR/teleport -- performing fresh install."
fi

if [ "$FRESH_INSTALL" = true ]; then
  mkdir -p "$BIN_DIR"
  if [ -f "$CONFIG_FILE" ]; then
    info "Existing config found at $CONFIG_FILE, keeping it."
  else
    [ -z "$AUTH_TOKEN" ] && error "Fresh install requires a join token. Usage: bash $0 <auth_token> [cluster_name]"
    [ -z "$CA_PIN" ] && error "CA_PIN is not set. Set it in this script or export TELEPORT_CA_PIN=sha256:..."
    CLUSTER_NAME=$(DETECT_CLUSTER_NAME)
    WRITE_CONFIG
  fi
  INSTALL_BINARY
  CURRENT_VERSION=$("$BIN_DIR/teleport" version 2>/dev/null | awk '{print $2}' | sed 's/v//')
  info "Installed version: $CURRENT_VERSION"
  [ "$CURRENT_VERSION" != "$TARGET_VERSION" ] && error "Version mismatch after install. Expected $TARGET_VERSION, got $CURRENT_VERSION"
else
  [ ! -f "$CONFIG_FILE" ] && error "Teleport config not found at $CONFIG_FILE."
  [ -n "$AUTH_TOKEN" ] && warn "Existing install detected -- ignoring join token argument (config at $CONFIG_FILE is left unchanged)."
  CURRENT_VERSION=$("$BIN_DIR/teleport" version 2>/dev/null | awk '{print $2}' | sed 's/v//')
  info "Current version: $CURRENT_VERSION"
fi
info "Target version:  $TARGET_VERSION"

VERSION_ALREADY_CORRECT=false
if [ "$FRESH_INSTALL" = false ] && [ "$CURRENT_VERSION" = "$TARGET_VERSION" ]; then
  VERSION_ALREADY_CORRECT=true
  warn "Already on target version $TARGET_VERSION -- skipping binary swap, but still ensuring the service is installed, enabled, and running (idempotent)."
fi

# ── Install/refresh systemd unit (idempotent regardless of version state) ────
if [ "$USE_SYSTEMD" = true ]; then
  WRITE_UNIT_FILE
fi

# ── If already on target version and running, nothing to do ─────────────────
# Otherwise (e.g. Teleport running via nohup rather than systemd, or stopped)
# fall through to START_SERVICE, which takes it over, and verify it connects.
if [ "$VERSION_ALREADY_CORRECT" = true ]; then
  if [ "$USE_SYSTEMD" = true ] && SERVICE_IS_ACTIVE; then
    info "Teleport service already running on target version. Nothing to do."
    SYSTEMCTL enable "$SERVICE_NAME" >/dev/null
    exit 0
  elif [ "$USE_SYSTEMD" = false ] && pgrep -f "${BIN_DIR}/teleport" >/dev/null 2>&1; then
    info "Teleport already running on target version. Nothing to do."
    exit 0
  fi
  warn "Teleport service not currently running -- starting it."
fi

# ── Upgrade path: stop, back up, swap binary ─────────────────────────────────
BACKUP_PATH=""
if [ "$FRESH_INSTALL" = false ] && [ "$VERSION_ALREADY_CORRECT" = false ]; then
  STOP_SERVICE

  # Backup old binary (skip if a backup for this version already exists)
  BACKUP_PATH="$BIN_DIR/teleport.bak.${CURRENT_VERSION}"
  if [ -f "$BACKUP_PATH" ]; then
    info "Backup for v${CURRENT_VERSION} already exists at $BACKUP_PATH, skipping."
  else
    info "Backing up current binary..."
    cp "$BIN_DIR/teleport" "$BACKUP_PATH"
    info "Backup saved to $BACKUP_PATH"
  fi

  INSTALL_BINARY

  NEW_VERSION=$("$BIN_DIR/teleport" version 2>/dev/null | awk '{print $2}' | sed 's/v//')
  info "Installed version: $NEW_VERSION"
  [ "$NEW_VERSION" != "$TARGET_VERSION" ] && error "Version mismatch after install. Expected $TARGET_VERSION, got $NEW_VERSION"
fi

# ── Start teleport (systemd: enabled + restarted; fallback: nohup) ───────────
START_SERVICE

# ── Wait for successful connection ────────────────────────────────────────────
info "Waiting for Teleport to connect (timeout: 60s)..."
TIMEOUT=60
ELAPSED=0
SUCCESS=false

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
  if [ "$USE_SYSTEMD" = true ]; then
    if ! SERVICE_IS_ACTIVE; then
      echo ""
      error "Teleport service failed to stay running. Check logs: journalctl -u ${SERVICE_NAME} -n 100 --no-pager"
    fi
  else
    if ! pgrep -f "${BIN_DIR}/teleport" >/dev/null 2>&1; then
      echo ""
      error "Teleport process died unexpectedly. Check logs: cat $LOG_FILE"
    fi
  fi

  # Only look at log lines written since START_SERVICE; older ones may be from
  # the previous (e.g. manually started) process. grep -c (not -q) reads all
  # input so tail never gets SIGPIPE under pipefail.
  MATCHES=$(tail -c "+$((LOG_OFFSET + 1))" "$LOG_FILE" 2>/dev/null \
    | grep -cE "Successfully registered via proxy server|Successfully obtained credentials|Service is starting in tunnel mode" || true)
  if [ "${MATCHES:-0}" -gt 0 ]; then
    SUCCESS=true
    break
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
  echo -n "."
done
echo ""

# ── Result ────────────────────────────────────────────────────────────────────
if [ "$SUCCESS" = true ]; then
  if [ "$FRESH_INSTALL" = true ]; then
    info "Install successful! Teleport v${TARGET_VERSION} connected."
  elif [ "$VERSION_ALREADY_CORRECT" = true ]; then
    info "Teleport v${TARGET_VERSION} started and connected."
  else
    info "Upgrade successful! Teleport v${TARGET_VERSION} connected."
  fi
  info "Logs: $LOG_FILE"
  if [ "$USE_SYSTEMD" = true ]; then
    info "Service is enabled and will survive reboots and auto-restart on crash."
    info "Manage it with: systemctl [status|stop|start|restart] ${SERVICE_NAME}"
  else
    warn "Running without systemd -- this process will NOT survive a reboot."
    warn "Install systemd (or another process supervisor) for reboot-safe operation."
  fi
else
  warn "Teleport did not confirm connection within ${TIMEOUT}s."
  if [ "$FRESH_INSTALL" = true ]; then
    warn "Check logs: tail -f $LOG_FILE"
    warn "Verify the join token is valid/unexpired and the proxy ($PROXY_SERVER) is reachable."
  elif [ "$VERSION_ALREADY_CORRECT" = true ]; then
    if [ "$USE_SYSTEMD" = true ]; then
      warn "Check logs: journalctl -u ${SERVICE_NAME} -n 100 --no-pager  (or: tail -f $LOG_FILE)"
    else
      warn "Check logs: tail -f $LOG_FILE"
    fi
  elif [ "$USE_SYSTEMD" = true ]; then
    warn "Check logs: journalctl -u ${SERVICE_NAME} -n 100 --no-pager  (or: tail -f $LOG_FILE)"
    warn "To rollback:"
    warn "  systemctl stop ${SERVICE_NAME}"
    warn "  cp $BACKUP_PATH $BIN_DIR/teleport"
    warn "  systemctl start ${SERVICE_NAME}"
  else
    warn "Check logs: tail -f $LOG_FILE"
    warn "To rollback:"
    warn "  pkill -f ${BIN_DIR}/teleport"
    warn "  cp $BACKUP_PATH $BIN_DIR/teleport"
    warn "  nohup ${BIN_DIR}/teleport start --config=${CONFIG_FILE} >> $LOG_FILE 2>&1 &"
  fi
  exit 1
fi
