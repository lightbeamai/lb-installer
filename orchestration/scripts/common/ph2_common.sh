#!/bin/bash
# ph2_common.sh — Self-contained functions for phase 2 (configure & join) scripts.
#
# No dependency on common.sh, prepare.sh, packages.sh, or OS files.
# Sourced by master_ctrl.sh, worker_ctrl.sh, and worker_edge.sh.

# ---------------------------------------------------------------------------
# Logging and utility functions
# ---------------------------------------------------------------------------

STEP_ID=0

log_step() {
  STEP_ID=$((STEP_ID + 1))
  echo ""
  echo "============================================================"
  printf 'STEP %02d: %s\n' "$STEP_ID" "$1"
  echo "============================================================"
}

require_binary() {
  local bin="$1"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERROR: required binary not found: $bin"
    exit 1
  fi
}

dotCount=0
maxDots=15
SLEEP_INTERVAL=5
TIMEOUT=300

showMessage() {
  local msg="$1"
  local dc=$dotCount
  if [[ $dc -eq 0 ]]; then
    local len=${#msg}
    len=$((len + maxDots))
    local filler=""
    local i=0
    while (( i < len )); do
      filler="$filler "
      i=$((i + 1))
    done
    echo -ne "\r${filler}"
    dc=1
  else
    local dots=""
    local i=0
    while (( i < dc )); do
      dots="${dots}."
      i=$((i + 1))
    done
    echo -ne "\r${msg}${dots}"
    dc=$((dc + 1))
    if (( dc >= maxDots )); then
      dc=0
    fi
  fi
  dotCount=$dc
}

serviceStatusCheck() {
  local service="$1"
  local exit_required="${2:-False}"
  local timeCheck=0
  while true; do
    local status
    status="$(systemctl is-active "$service" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\r')"
    if [[ "$status" == "active" ]]; then
      echo ""
      echo "$service running.."
      break
    fi
    showMessage "$service status check"
    sleep "$SLEEP_INTERVAL"
    timeCheck=$((timeCheck + SLEEP_INTERVAL))
    if (( timeCheck > TIMEOUT )); then
      echo ""
      echo "$service not running, Timeout error."
      echo ""
      if [[ "$exit_required" == "True" ]]; then
        exit 1
      fi
      break
    fi
  done
}

# ---------------------------------------------------------------------------
# Firewall (OS-agnostic)
# ---------------------------------------------------------------------------

disable_host_firewall() {
  # Try firewalld (RHEL/CentOS)
  if systemctl is-active --quiet firewalld 2>/dev/null; then
    systemctl disable --now firewalld || true
    echo "firewalld disabled"
    return 0
  fi

  # Try ufw (Ubuntu/Debian)
  local ufw_bin=""
  if command -v ufw >/dev/null 2>&1; then
    ufw_bin="$(command -v ufw)"
  elif [ -x /usr/sbin/ufw ]; then
    ufw_bin="/usr/sbin/ufw"
  fi

  if [ -n "$ufw_bin" ]; then
    if systemctl is-enabled ufw >/dev/null 2>&1 || systemctl is-active ufw >/dev/null 2>&1; then
      "$ufw_bin" disable || true
      echo "ufw disabled"
    else
      echo "UFW not enabled, skipping firewall disable"
    fi
    return 0
  fi

  echo "No firewall found to disable"
}

# ---------------------------------------------------------------------------
# Docker prune cron (master only)
# ---------------------------------------------------------------------------

setup_docker_prune_cron() {
  echo "Setting up Docker prune cron job..."
  cat > /etc/cron.d/lightbeam-docker-prune <<'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 3 1 * * root /usr/bin/docker system prune -af > /var/log/docker_prune.log 2>&1
EOF
  chmod 644 /etc/cron.d/lightbeam-docker-prune

  if systemctl list-unit-files 2>/dev/null | grep -q '^cron\.service'; then
    systemctl enable --now cron || true
  elif systemctl list-unit-files 2>/dev/null | grep -q '^crond\.service'; then
    systemctl enable --now crond || true
  fi

  echo "Docker prune cron job configured at /etc/cron.d/lightbeam-docker-prune."
}

# ---------------------------------------------------------------------------
# Container runtime setup
# ---------------------------------------------------------------------------

# common_run_container_setup — for master nodes (Docker + containerd).
common_run_container_setup() {
  log_step "Configure container runtime"
  systemctl enable --now containerd docker
  local docker_status
  docker_status=$(systemctl status docker | grep "running" | wc -l)
  echo "$docker_status"
  if [[ "$docker_status" == 1 ]]; then
    echo "Docker installed and running .."
  else
    echo "Docker installed but not running.."
  fi

  mkdir -p /etc/docker
  cat <<'EOF' > /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF
  systemctl restart docker
  sleep 10
  local cgroupdriver_status
  cgroupdriver_status=$(docker info | grep -i "Cgroup Driver" | grep systemd | wc -l)
  if [[ "$cgroupdriver_status" == 1 ]]; then
    echo "Docker cgroup driver is updated to systemd"
  else
    echo "Failed to update docker cgroup driver to systemd"
    exit 1
  fi

  setup_docker_prune_cron

  echo "Disabling swap..."
  swapoff -a
  sed -e '/swap/ s/^#*/#/' -i /etc/fstab
  systemctl mask swap.target

  if command -v setenforce >/dev/null 2>&1; then
    setenforce 0
    sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
  fi

  disable_host_firewall

  mkdir -p /etc/containerd
  containerd config default | tee /etc/containerd/config.toml >/dev/null
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  systemctl restart containerd

  modprobe overlay
  modprobe br_netfilter

  cat <<'EOF' > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

  cat <<'EOF' > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

  sysctl --system
}

# common_worker_container_setup — for worker nodes (containerd only, no Docker).
common_worker_container_setup() {
  log_step "Configure container runtime (worker)"

  echo "Disabling swap..."
  swapoff -a
  sed -e '/swap/ s/^#*/#/' -i /etc/fstab
  systemctl mask swap.target

  if command -v setenforce >/dev/null 2>&1; then
    setenforce 0
    sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
  fi

  disable_host_firewall

  mkdir -p /etc/containerd
  containerd config default | tee /etc/containerd/config.toml >/dev/null
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  systemctl daemon-reload
  systemctl enable containerd
  systemctl restart containerd
  echo "✓ Containerd configured"

  modprobe overlay
  modprobe br_netfilter

  cat <<'EOF' > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

  cat <<'EOF' > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

  sysctl --system
}

# ---------------------------------------------------------------------------
# Kubernetes binary configuration
# ---------------------------------------------------------------------------

common_install_kubernetes_binaries() {
  log_step "Enable Kubernetes binaries"

  for bin in kubelet kubeadm kubectl; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      echo "ERROR: ${bin} was not installed successfully"
      exit 1
    fi
  done

  systemctl daemon-reload
  systemctl enable kubelet
  systemctl start kubelet
}

# ---------------------------------------------------------------------------
# WireGuard watchdog
# ---------------------------------------------------------------------------

install_wg_watchdog() {
  local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
  local watchdog="${script_dir}/wireguard-watchdog.sh"
  if [[ ! -f "$watchdog" ]]; then
    echo "WARNING: wireguard-watchdog.sh not found at $watchdog; skipping."
    return 0
  fi
  echo "Installing WireGuard watchdog..."
  WATCHDOG_SOURCE="$watchdog" \
    WG_IFACE=wg0 \
    WATCHDOG_MODE=interface \
    WATCHDOG_INTERVAL=2m \
    bash "$watchdog" install || true
  echo "✓ WireGuard watchdog installed"
}
