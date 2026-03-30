#!/bin/bash
# run_migration.sh — Disk migration function (AWS EBS secondary disk).
#
# Detects the secondary (non-boot) EBS volume and bind-mounts /var/lib
# subdirectories onto it so that container, kubelet, and etcd data
# persists across instance replacements (image upgrades).
#
# Self-contained: no dependency on packages.sh or prepare.sh.
# Sourced by master_ctrl.sh and worker_ctrl.sh.

# ---------------------------------------------------------------------------
# Disk migration (AWS EBS secondary disk → /mnt/k8s-data bind mounts)
# ---------------------------------------------------------------------------

run_common_migration() {
  # Find the secondary disk (any attached disk that is NOT the boot disk).
  # The boot disk is the one mounted at / — we skip it.
  local BOOT_DEVICE=""
  BOOT_DEVICE=$(lsblk -ndo PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null || true)

  local DEVICE=""
  while read -r name size type; do
    if [[ "$type" == "disk" && "$name" != "$BOOT_DEVICE" ]]; then
      DEVICE="/dev/$name"
      echo "Detected secondary disk: $DEVICE ($(( size / 1024 / 1024 / 1024 )) GB)"
      break
    fi
  done < <(lsblk -bdn -o NAME,SIZE,TYPE)

  if [[ -z "$DEVICE" || ! -b "$DEVICE" ]]; then
    echo "WARNING: No secondary disk detected. Skipping data disk migration."
    echo "  All data will be on the boot disk (not persistent across image upgrades)."
    return 0
  fi

  # Format if unformatted (first boot only)
  if ! blkid "$DEVICE" >/dev/null 2>&1; then
    echo "Formatting $DEVICE as ext4..."
    mkfs.ext4 -F "$DEVICE"
  fi

  # Mount to /mnt/k8s-data
  echo "Mounting $DEVICE to /mnt/k8s-data"
  mkdir -p /mnt/k8s-data
  if ! mountpoint -q /mnt/k8s-data; then
    mount "$DEVICE" /mnt/k8s-data
    local UUID
    UUID=$(blkid -s UUID -o value "$DEVICE")
    if ! grep -q "$UUID" /etc/fstab; then
      echo "UUID=$UUID /mnt/k8s-data ext4 defaults,nofail 0 2" >> /etc/fstab
    fi
  fi

  # Create subdirectories and set up bind mounts
  mkdir -p /mnt/k8s-data/{containerd,kubelet,etcd}
  mkdir -p /var/lib/containerd /var/lib/kubelet /var/lib/etcd

  if ! mountpoint -q /var/lib/containerd; then mount --bind /mnt/k8s-data/containerd /var/lib/containerd; fi
  if ! mountpoint -q /var/lib/kubelet;    then mount --bind /mnt/k8s-data/kubelet    /var/lib/kubelet;    fi
  if ! mountpoint -q /var/lib/etcd;       then mount --bind /mnt/k8s-data/etcd       /var/lib/etcd;       fi

  # Persist bind mounts in fstab
  if ! grep -q "/mnt/k8s-data/containerd" /etc/fstab; then
    echo "/mnt/k8s-data/containerd /var/lib/containerd none bind 0 0" >> /etc/fstab
    echo "/mnt/k8s-data/kubelet    /var/lib/kubelet    none bind 0 0" >> /etc/fstab
    echo "/mnt/k8s-data/etcd       /var/lib/etcd       none bind 0 0" >> /etc/fstab
  fi

  # Control plane PKI: pass "ctrl" as first argument to also bind-mount /etc/kubernetes/pki
  if [[ "${1:-}" == "ctrl" ]]; then
    mkdir -p /mnt/k8s-data/pki /etc/kubernetes/pki
    if ! mountpoint -q /etc/kubernetes/pki; then
      mount --bind /mnt/k8s-data/pki /etc/kubernetes/pki
    fi
    if ! grep -q "/mnt/k8s-data/pki" /etc/fstab; then
      echo "/mnt/k8s-data/pki /etc/kubernetes/pki none bind 0 0" >> /etc/fstab
    fi
    echo "  PKI bind mount: /mnt/k8s-data/pki → /etc/kubernetes/pki"
  fi

  echo "Data disk migration complete: $DEVICE → /mnt/k8s-data"
}
