#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Force IPv4 and disable IPv6 — EC2 instances may have broken IPv6 routes,
# and private-subnet instances cannot reach security.ubuntu.com over IPv4
# without a NAT gateway.  The EC2 regional mirror is accessible internally.
_region=$(curl -s --connect-timeout 3 \
  http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || true)
_region=$(printf '%s' "$_region" | head -n 1 | tr -d '\r')
if [[ ! "$_region" =~ ^[a-z]{2}(-gov)?-[a-z0-9-]+-[0-9]+$ ]]; then
  _region="us-east-1"
fi
echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true
_ec2_mirror="http://${_region}.ec2.archive.ubuntu.com/ubuntu"
sed -i "s|http://security.ubuntu.com/ubuntu|${_ec2_mirror}|g" \
  /etc/apt/sources.list 2>/dev/null || true
sed -i "s|http://\.ec2.archive.ubuntu.com/ubuntu|${_ec2_mirror}|g" \
  /etc/apt/sources.list 2>/dev/null || true
[ -f /etc/apt/sources.list.d/ubuntu.sources ] && \
  sed -i "s|http://security.ubuntu.com/ubuntu|${_ec2_mirror}|g" \
    /etc/apt/sources.list.d/ubuntu.sources || true
[ -f /etc/apt/sources.list.d/ubuntu.sources ] && \
  sed -i "s|http://\.ec2.archive.ubuntu.com/ubuntu|${_ec2_mirror}|g" \
    /etc/apt/sources.list.d/ubuntu.sources || true

# Refresh apt metadata first so package discovery works on fresh instances.
timeout 120 apt-get update -y

# wg-quick/wg come from wireguard-tools.
timeout 180 apt-get install -y --no-install-recommends \
  wireguard-tools nginx ca-certificates iptables-persistent netfilter-persistent

# Prefer distro awscli package; fall back to AWS CLI v2 installer if unavailable.
if ! command -v aws >/dev/null 2>&1; then
  if ! timeout 120 apt-get install -y --no-install-recommends awscli; then
    timeout 120 apt-get install -y --no-install-recommends curl unzip
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' EXIT
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "${tmpdir}/awscliv2.zip"
    unzip -q "${tmpdir}/awscliv2.zip" -d "${tmpdir}"
    "${tmpdir}/aws/install" --update
    rm -rf "${tmpdir}"
    trap - EXIT
  fi
fi
# Install udp2raw binary if available in bundle
if [[ -f /tmp/udp2raw_amd64 ]]; then
  install -m 755 /tmp/udp2raw_amd64 /usr/local/bin/udp2raw
  rm -f /tmp/udp2raw_binaries.tar.gz /tmp/udp2raw_amd64
elif ! command -v udp2raw >/dev/null 2>&1; then
  log "Downloading udp2raw..."
  wget -q -O /tmp/udp2raw_binaries.tar.gz \
    https://github.com/wangyu-/udp2raw/releases/download/20230206.0/udp2raw_binaries.tar.gz
  tar -xf /tmp/udp2raw_binaries.tar.gz -C /tmp/
  install -m 755 /tmp/udp2raw_amd64 /usr/local/bin/udp2raw
  rm -f /tmp/udp2raw_binaries.tar.gz /tmp/udp2raw_amd64
fi

command -v wg >/dev/null 2>&1 || { echo "ERROR: wg binary not found after package install"; exit 1; }
command -v nginx >/dev/null 2>&1 || { echo "ERROR: nginx binary not found after package install"; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI not found after package install"; exit 1; }
command -v netfilter-persistent >/dev/null 2>&1 || {
  echo "ERROR: netfilter-persistent not found after package install"
  exit 1
}

echo PACKAGES_DONE
