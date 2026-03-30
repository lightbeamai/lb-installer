# Orchestration Scripts Reference Map

This document captures script usage across the four orchestration entrypoints:

- `aws-kubeadm` (A)
- `gcp-kubeadm` (G)
- `aws-edge` (E)
- `gcp-edge` (H)

Set logic used:

- **2** = `A ∩ G ∩ E ∩ H`
- **3** = `(A ∩ G) - 2`
- **6** = `(E ∩ H) - 2`
- **4** = `A - (G ∪ E ∪ H)`
- **5** = `G - (A ∪ E ∪ H)`
- **7** = `E - (A ∪ G ∪ H)`
- **8** = `H - (A ∪ G ∪ E)`

## 1) Unused Scripts

- `scripts/ctrl/cloud/aws_readiness_probe.sh`
- `scripts/ctrl/cloud/gcp_readiness_probe.sh`
- `scripts/ctrl/cloud/install-ssm-agent.sh`
- `scripts/ctrl/cluster_tunnel_readiness_probe.sh`

## 2) Referenced By All 4 (`A ∩ G ∩ E ∩ H`)

- None

## 3) Referenced By Both `aws-kubeadm` and `gcp-kubeadm`, Excluding #2 (`(A ∩ G) - 2`)

- `scripts/ctrl/common.sh`
- `scripts/ctrl/master_common.sh`
- `scripts/ctrl/os/common_rhel.sh`
- `scripts/ctrl/os/common_ubuntu.sh`
- `scripts/ctrl/os/master_rhel.sh`
- `scripts/ctrl/os/master_ubuntu.sh`
- `scripts/ctrl/os/worker_rhel.sh`
- `scripts/ctrl/os/worker_ubuntu.sh`
- `scripts/common/wireguard-watchdog.sh`
- `scripts/ctrl/worker_common.sh`

## 4) Referenced Only By `aws-kubeadm` (`A - (G ∪ E ∪ H)`)

- `scripts/ctrl/generate-edge-scripts.sh`
- `scripts/node/check_workers_ready.sh`
- `scripts/node/cp_preconfig.sh`
- `scripts/node/gateway_nat.sh`
- `scripts/node/gateway_nginx.sh`
- `scripts/node/gateway_packages.sh`
- `scripts/node/gateway_wireguard.sh`
- `scripts/node/show_nodes.sh`

## 5) Referenced Only By `gcp-kubeadm` (`G - (A ∪ E ∪ H)`)

- None

## 6) Referenced By Both `aws-edge` and `gcp-edge`, Excluding #2 (`(E ∩ H) - 2`)

- `scripts/ctrl/cloud/aws_token.sh`
- `scripts/ctrl/cloud/gcp_token.sh`
- `scripts/edge/discovery-kubeconfig.sh`
- `scripts/edge/worker_rhel.sh`
- `scripts/edge/worker_ubuntu.sh`

## 7) Referenced Only By `aws-edge` (`E - (A ∪ G ∪ H)`)

- `scripts/node/vpn_probe.sh`
- `scripts/node/worker_state_probe.sh`
- `scripts/node/write_env_file.sh`

## 8) Referenced Only By `gcp-edge` (`H - (A ∪ G ∪ E)`)

- None

## Notes

- This is a static reference map from current code paths (installer manifests, shell sourcing, and AWS node-script dispatch).
- Recompute this file after major refactors to keep it accurate.
