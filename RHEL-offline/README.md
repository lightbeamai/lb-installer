# RHEL Offline Installer

Scripts for deploying a LightBeam Kubernetes cluster on air-gapped RHEL 9 (x86_64) machines.

## Overview

The workflow has two phases:

1. **Build** – Run on an internet-connected RHEL 9 machine to download all dependencies into a tarball.
2. **Deploy** – Transfer the tarball to air-gapped machines and run the setup scripts.

## Scripts

| Script | Where to run | Purpose |
|--------|-------------|---------|
| `build-offline-bundle-rhel9.sh` | Internet-connected RHEL 9 | Downloads all dependencies and creates `lb-offline-bundle-rhel9.tar.gz` |
| `install-offline-bundle-rhel9.sh` | Air-gapped machine (inside bundle) | Installs RPMs and Helm without full cluster setup |
| `master-offline.sh` | Air-gapped master node | Full control-plane setup (Docker, Kubernetes, Calico, LightBeam service) |
| `worker-offline.sh` | Air-gapped worker node | Worker node setup (Docker, Kubernetes, kubelet) |

## What the bundle contains

- Docker CE RPMs (`docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`)
- Kubernetes v1.34 RPMs (`kubelet`, `kubeadm`, `kubectl`)
- RHEL 9 base dependency RPMs (`container-selinux`, `iptables-nft`, `nftables`, `wget`, `selinux-policy`, etc.)
- Helm v3.13.1 (static binary)
- Calico v3.29.0 manifest
- Docker and Kubernetes GPG keys
- `install-offline-bundle-rhel9.sh`

---

## Step 1 — Build the bundle (internet-connected machine)

Run on a minimal RHEL 9 x86_64 machine with internet access:

```bash
sudo bash build-offline-bundle-rhel9.sh
```

This produces `lb-offline-bundle-rhel9.tar.gz` in the current directory.

Transfer the tarball to each air-gapped machine:

```bash
scp lb-offline-bundle-rhel9.tar.gz user@<air-gapped-host>:~
```

---

## Step 2 — Extract the bundle (air-gapped machine)

On each air-gapped machine:

```bash
tar -xzf lb-offline-bundle-rhel9.tar.gz
```

This creates the directory `lb-offline-bundle-rhel9/`.

---

## Step 3 — Set up the master node

```bash
sudo bash master-offline.sh lb-offline-bundle-rhel9
```

The script will:
- Install Docker CE and configure the `systemd` cgroup driver
- Install `kubelet`, `kubeadm`, `kubectl`
- Install Helm v3.13.1
- Disable swap, set SELinux to permissive, disable firewalld
- Configure kernel modules (`overlay`, `br_netfilter`) and sysctl params
- Initialize the cluster: `kubeadm init --pod-network-cidr=192.168.0.0/16`
- Deploy Calico CNI from the bundled manifest
- Patch Calico to use `vxlanMode: Always` if IP-in-IP is not permitted
- Create and enable the `lightbeam.service` systemd service (port-forwards Kong proxy on 80/443)
- Pin all package versions with `dnf versionlock`

After the script completes, it prints a `kubeadm join` command. Save this — you will need it for each worker node.

---

## Step 4 — Set up worker nodes

On each worker node:

```bash
sudo bash worker-offline.sh lb-offline-bundle-rhel9
```

The script will:
- Install Docker CE and configure the `systemd` cgroup driver
- Install `kubelet`, `kubeadm`, `kubectl`
- Disable swap, set SELinux to permissive, disable firewalld
- Configure kernel modules and sysctl params
- Enable and start `kubelet`
- Pin all package versions with `dnf versionlock`

Then join the worker to the cluster using the `kubeadm join` command printed by the master script:

```bash
sudo kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

---

## Alternative: install-offline-bundle-rhel9.sh

If you only need to install Docker, Kubernetes packages, and Helm without initializing a cluster (e.g., to prepare a node before running your own `kubeadm` commands), use the script bundled inside the extracted directory:

```bash
sudo bash lb-offline-bundle-rhel9/install-offline-bundle-rhel9.sh
```

---

## Requirements

- RHEL 9, x86_64
- Root / sudo access on all machines
- The build machine must have internet access
- Air-gapped machines must have no internet access requirement (all deps are in the bundle)

## Notes

- All scripts must be run as root (`sudo` or `su`).
- The bundle path passed to `master-offline.sh` and `worker-offline.sh` must point to the extracted directory (containing the `rpms/`, `helm/`, and `manifests/` subdirectories), not the tarball.
- Package versions are locked after installation to prevent unintended upgrades.
