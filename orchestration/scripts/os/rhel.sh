#!/bin/bash
# rhel.sh — RHEL/CentOS/Fedora-specific package installation functions.
#
# Sourced by scripts/common/packages.sh after OS detection.
# Covers both ctrl-plane and edge node deployments.

remove_old_packages() {
  dnf remove -y docker docker-ce docker-ce-cli containerd.io containerd runc \
    kubeadm kubelet kubectl || true
}

install_common_dependencies() {
  dnf install -y epel-release \
    || dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
  dnf install -y \
    ca-certificates curl gnupg2 jq conntrack-tools socat nmap-ncat \
    iptables wget tar wireguard-tools
}

install_container_runtime() {
  remove_old_packages
  dnf install -y dnf-plugins-core
  dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
  dnf install -y \
    ca-certificates curl gnupg2 openssh-server wget tar \
    docker-ce docker-ce-cli containerd.io
}

# Alias: edge worker_edge.sh uses this name.
install_containerd_runtime() { install_container_runtime; }

prepare_kubernetes_repo() {
  cat > /etc/yum.repos.d/kubernetes.repo <<'REPO_EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
REPO_EOF
}

install_kubernetes_rpms() {
  dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
}

# Combined: ctrl-plane scripts use this single-step version.
install_kubernetes_packages() {
  prepare_kubernetes_repo
  install_kubernetes_rpms
}

install_wireguard_tools() {
  dnf install -y epel-release \
    || dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
  dnf install -y wireguard-tools
}

install_bash_completion_pkg() {
  dnf install -y bash-completion
}

install_iptables_persistence() {
  dnf install -y iptables-services
  iptables-save > /etc/sysconfig/iptables
  systemctl enable iptables
  systemctl restart iptables
}

# Backward-compat alias.
persist_iptables_rules() { install_iptables_persistence; }

disable_host_firewall() {
  systemctl disable --now firewalld || true
}

hold_installed_packages() {
  dnf install -y 'dnf-command(versionlock)' || true
  dnf versionlock add \
    kubelet kubeadm kubectl containerd.io docker-ce docker-ce-cli || true
}
