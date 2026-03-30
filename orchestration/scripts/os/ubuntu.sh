#!/bin/bash
# ubuntu.sh — Ubuntu/Debian-specific package installation functions.
#
# Sourced by scripts/common/packages.sh after OS detection.
# Covers both ctrl-plane and edge node deployments.

# Configure apt and networking for EC2 compatibility.
#
# Two problems addressed here:
#   1. IPv6 unreachable  — EC2 instances may have IPv6 configured but broken
#      routes to package mirrors.  ForceIPv4 + sysctl prevent any IPv6 attempt.
#   2. security.ubuntu.com unreachable over IPv4 — instances in private subnets
#      without a NAT gateway cannot reach external Ubuntu servers.  The EC2
#      regional mirror carries the same packages (including security updates)
#      and is accessible internally through AWS infrastructure.
_configure_apt_for_ec2() {
  # Detect AWS region from EC2 instance metadata; fall back to us-east-1.
  local region
  region="$(curl -s --connect-timeout 3 \
    http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || true)"
  region="$(printf '%s' "$region" | head -n 1 | tr -d '\r')"

  # Only treat as AWS when region shape is valid (e.g. us-east-1, us-gov-west-1).
  if [[ ! "$region" =~ ^[a-z]{2}(-gov)?-[a-z0-9-]+-[0-9]+$ ]]; then
    region=""
  fi

  # No-op outside AWS; keep default distro mirrors unchanged.
  if [[ -z "$region" ]]; then
    # Self-heal prior bad rewrites from older logic.
    if [ -f /etc/apt/sources.list ]; then
      sed -i "s|http://\.ec2.archive.ubuntu.com/ubuntu|http://security.ubuntu.com/ubuntu|g" /etc/apt/sources.list
    fi
    if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
      sed -i "s|http://\.ec2.archive.ubuntu.com/ubuntu|http://security.ubuntu.com/ubuntu|g" /etc/apt/sources.list.d/ubuntu.sources
    fi
    return 0
  fi

  local ec2_mirror="http://${region}.ec2.archive.ubuntu.com/ubuntu"

  # Force apt to use IPv4 only.
  echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4

  # Disable IPv6 at the kernel level for this session so other tools
  # (curl, etc.) also avoid unreachable IPv6 routes.
  sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true

  # Redirect security.ubuntu.com to the EC2 regional mirror.
  # Handles both the legacy sources.list and the Ubuntu 24.04 DEB822 format.
  if [ -f /etc/apt/sources.list ]; then
    sed -i "s|http://security.ubuntu.com/ubuntu|${ec2_mirror}|g" /etc/apt/sources.list
    sed -i "s|http://\.ec2.archive.ubuntu.com/ubuntu|${ec2_mirror}|g" /etc/apt/sources.list
  fi
  if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    sed -i "s|http://security.ubuntu.com/ubuntu|${ec2_mirror}|g" /etc/apt/sources.list.d/ubuntu.sources
    sed -i "s|http://\.ec2.archive.ubuntu.com/ubuntu|${ec2_mirror}|g" /etc/apt/sources.list.d/ubuntu.sources
  fi
}
_configure_apt_for_ec2

_refresh_docker_apt_repo() {
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
}

remove_old_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-mark unhold kubelet kubeadm kubectl containerd.io docker-ce docker-ce-cli 2>/dev/null || true
  apt-get -y --allow-change-held-packages remove docker docker-engine docker.io containerd runc \
    kubeadm kubelet kubectl || true
}

install_common_dependencies() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --allow-change-held-packages \
    apt-transport-https nginx ca-certificates curl gnupg lsb-release \
    wireguard wireguard-tools iptables jq conntrack socat netcat-openbsd
}

install_container_runtime() {
  remove_old_packages
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --allow-change-held-packages \
    apt-transport-https ca-certificates curl gnupg-agent \
    software-properties-common openssh-server
  _refresh_docker_apt_repo
  apt-get update -y
  apt-get install -y --allow-change-held-packages --allow-change-held-packages docker-ce docker-ce-cli containerd.io
}

# Alias: edge worker_edge.sh uses this name.
install_containerd_runtime() { install_container_runtime; }

prepare_kubernetes_repo() {
  export DEBIAN_FRONTEND=noninteractive
  rm -f /etc/apt/sources.list.d/kubernetes.list
  rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  apt-get update -y
  apt-get install -y --allow-change-held-packages apt-transport-https ca-certificates curl gpg
  mkdir -p /etc/apt/keyrings
}

install_kubernetes_rpms() {
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
  apt-get update -y
  apt-get install -y --allow-change-held-packages kubelet=1.33.0-1.1 kubeadm=1.33.0-1.1 kubectl=1.33.0-1.1
}

# Combined: ctrl-plane scripts use this single-step version.
install_kubernetes_packages() {
  export DEBIAN_FRONTEND=noninteractive
  rm -f /etc/apt/sources.list.d/kubernetes.list
  rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  apt-get update -y
  apt-get install -y --allow-change-held-packages apt-transport-https ca-certificates curl gpg
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key -o /tmp/k8s-key.gpg
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg /tmp/k8s-key.gpg
  rm -f /tmp/k8s-key.gpg
  cat > /etc/apt/sources.list.d/kubernetes.list <<'REPO_EOF'
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /
REPO_EOF
  apt-get update -y
  apt-get install -y --allow-change-held-packages kubelet=1.33.0-1.1 kubeadm=1.33.0-1.1 kubectl=1.33.0-1.1
}

install_wireguard_tools() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y --allow-change-held-packages wireguard wireguard-tools
}

install_bash_completion_pkg() {
  export DEBIAN_FRONTEND=noninteractive
  # Refresh Docker repo key to avoid NO_PUBKEY failures during apt update on reruns.
  _refresh_docker_apt_repo || true
  apt-get update -y -o Acquire::Retries=3 || true
  apt-get install -y --allow-change-held-packages bash-completion
}

install_iptables_persistence() {
  echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
  echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
  DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-change-held-packages iptables-persistent
  netfilter-persistent save
}

# Backward-compat alias.
persist_iptables_rules() { install_iptables_persistence; }

disable_host_firewall() {
  local ufw_bin=""
  if command -v ufw >/dev/null 2>&1; then
    ufw_bin="$(command -v ufw)"
  elif [ -x /usr/sbin/ufw ]; then
    ufw_bin="/usr/sbin/ufw"
  fi

  if [ -z "$ufw_bin" ]; then
    echo "ufw binary not found, skipping firewall disable"
    return 0
  fi

  if systemctl is-enabled ufw >/dev/null 2>&1 || systemctl is-active ufw >/dev/null 2>&1; then
    "$ufw_bin" disable || true
  else
    echo "UFW not enabled, skipping firewall disable"
  fi
}

hold_installed_packages() {
  apt-mark hold \
    kubelet kubectl kubeadm \
    containerd.io \
    docker-buildx-plugin docker-ce docker-ce-cli \
    docker-ce-rootless-extras docker-compose-plugin \
    snapd systemd systemd-sysv systemd-timesyncd
}
