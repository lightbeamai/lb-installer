#!/bin/bash
# prepare.sh — System configuration helpers for ctrl-plane nodes.
#
# Covers logging utilities, container runtime setup, and Kubernetes node
# configuration.
#
# Sourced via common.sh (after packages.sh).

set -euo pipefail

# ---------------------------------------------------------------------------
# Logging utilities
# ---------------------------------------------------------------------------

STEP_ID=0

log_step() {
  STEP_ID=$((STEP_ID + 1))
  echo ""
  echo "============================================================"
  printf 'STEP %02d: %s\n' "$STEP_ID" "$1"
  echo "============================================================"
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
# Container runtime configuration
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

# common_run_container_setup installs the container runtime and applies all
# required system configuration (cgroup driver, kernel modules, sysctl, swap).
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

# common_worker_container_setup configures containerd (no Docker), disables swap,
# sets kernel modules, and applies sysctl settings. Used by worker nodes that
# don't need Docker running.
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

# common_install_kubernetes_binaries enables and starts kubelet after packages
# have already been installed by packages.sh.
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
