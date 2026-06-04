# Kubelet Node Protection

The Ubuntu Kubernetes installer configures kubelet reservations and hard eviction
thresholds so Pods cannot consume all node memory or local ephemeral storage
before kubelet has a chance to evict them. This helps keep control-plane,
worker, single-node, and future specialized nodes Ready under resource pressure.

This does not replace application-level resource requests and limits. It only
protects the node by reserving capacity for node daemons and by keeping eviction
headroom.

## What Is Configured

`kubeReserved` reserves capacity for Kubernetes node daemons such as kubelet and
the container runtime.

`systemReserved` reserves capacity for OS daemons such as systemd, sshd, udev,
kernel memory, and login sessions.

`evictionHard` tells kubelet when to evict Pods before memory or disk exhaustion
can make the node unstable.

`evictionMinimumReclaim` tells kubelet how much resource to reclaim once a hard
eviction threshold is crossed.

`mergeDefaultEvictionSettings: true` keeps Kubernetes defaults for any eviction
settings not explicitly listed.

`enforceNodeAllocatable` is set to `["pods"]`. The installer does not enforce
`system-reserved` or `kube-reserved` cgroups because this repo does not create
or validate those cgroups.

## Defaults

| Setting | Default |
| --- | --- |
| `kubeReserved.cpu` | `300m` |
| `kubeReserved.memory` | `512Mi` |
| `kubeReserved.ephemeral-storage` | `2Gi` |
| `kubeReserved.pid` | `1000` |
| `systemReserved.cpu` | `300m` |
| `systemReserved.memory` | `512Mi` |
| `systemReserved.ephemeral-storage` | `2Gi` |
| `systemReserved.pid` | `1000` |
| `evictionHard.memory.available` | `500Mi` |
| `evictionHard.nodefs.available` | `10%` |
| `evictionHard.nodefs.inodesFree` | `5%` |
| `evictionHard.imagefs.available` | `15%` |
| `evictionHard.imagefs.inodesFree` | `5%` |
| `evictionMinimumReclaim.memory.available` | `256Mi` |
| `evictionMinimumReclaim.nodefs.available` | `1Gi` |
| `evictionMinimumReclaim.imagefs.available` | `1Gi` |
| `enforceNodeAllocatable` | `pods` |

These defaults are conservative for modest Ubuntu nodes. Tune them upward for
larger nodes or nodes with heavy system/container-runtime overhead.

## Environment Overrides

All values can be changed without editing scripts:

```bash
LB_KUBE_RESERVED_CPU
LB_KUBE_RESERVED_MEMORY
LB_KUBE_RESERVED_EPHEMERAL_STORAGE
LB_KUBE_RESERVED_PID
LB_SYSTEM_RESERVED_CPU
LB_SYSTEM_RESERVED_MEMORY
LB_SYSTEM_RESERVED_EPHEMERAL_STORAGE
LB_SYSTEM_RESERVED_PID
LB_EVICTION_MEMORY_AVAILABLE
LB_EVICTION_NODEFS_AVAILABLE
LB_EVICTION_NODEFS_INODES_FREE
LB_EVICTION_IMAGEFS_AVAILABLE
LB_EVICTION_IMAGEFS_INODES_FREE
LB_EVICTION_RECLAIM_MEMORY_AVAILABLE
LB_EVICTION_RECLAIM_NODEFS_AVAILABLE
LB_EVICTION_RECLAIM_IMAGEFS_AVAILABLE
LB_ENFORCE_NODE_ALLOCATABLE
```

`LB_ENFORCE_NODE_ALLOCATABLE` is comma-separated. The default is `pods`.

## New Clusters

`Ubuntu/master.sh` writes a multi-document `kubeadm-config.yaml` containing:

1. `InitConfiguration`
2. `ClusterConfiguration`
3. `KubeletConfiguration`

Kubeadm writes this kubelet config to `/var/lib/kubelet/config.yaml` and uploads
the cluster-level config to `kube-system/kubelet-config`. Joining nodes inherit
that config through `kubeadm join`.

Example:

```bash
LB_KUBE_RESERVED_MEMORY=512Mi \
LB_SYSTEM_RESERVED_MEMORY=512Mi \
LB_EVICTION_MEMORY_AVAILABLE=500Mi \
sudo ./Ubuntu/master.sh
```

`Ubuntu/worker.sh` prepares Docker/containerd and kubelet for the same
systemd-cgroup model. If the worker has already joined and
`/var/lib/kubelet/config.yaml` exists, it applies the local node protection
settings. If it has not joined yet, run the apply script after `kubeadm join`
only if the node did not inherit the cluster config or you need local overrides.

## Existing Nodes

Run this on any control-plane, worker, or single-node cluster node:

```bash
sudo LB_EVICTION_MEMORY_AVAILABLE=500Mi ./scripts/apply-kubelet-node-protection.sh
sudo ./scripts/verify-kubelet-node-protection.sh
```

The apply script:

- requires root,
- checks or installs `python3-yaml` on Ubuntu,
- backs up `/var/lib/kubelet/config.yaml`,
- patches only the relevant top-level kubelet fields,
- validates the resulting YAML,
- restarts kubelet and waits for it to become active,
- optionally backs up and patches `kube-system/kubelet-config` when `kubectl`
  can reach the cluster.

## Verification

The verification script prints local kubelet settings and exits non-zero if
required fields are missing or unsafe. If `kubectl` is available, it also prints
the node, Capacity, Allocatable, and Ready/MemoryPressure/DiskPressure/PIDPressure
conditions.

```bash
sudo ./scripts/verify-kubelet-node-protection.sh
```

Set `LB_NODE_NAME=<node-name>` if the local hostname does not match the
Kubernetes node name.

## Destructive Validation

`scripts/validate-node-pressure-eviction.sh` intentionally creates memory and
optionally disk pressure on one selected node. It is for disposable clusters or
maintenance windows only. Do not run it on production nodes.

The script refuses to run without `--i-understand-this-is-destructive`. It also
refuses to target control-plane/master nodes unless `--allow-control-plane` is
provided. It uses a dedicated namespace, unprivileged Pods, no hostPath,
no hostPID, and no hostNetwork. Artifacts are written under
`artifacts/node-pressure-test-<timestamp>/`.

Validation on a worker:

```bash
./scripts/validate-node-pressure-eviction.sh \
  --node worker-1 \
  --mode memory \
  --i-understand-this-is-destructive
```

Validation on a control-plane node:

```bash
./scripts/validate-node-pressure-eviction.sh \
  --node master-1 \
  --mode memory \
  --allow-control-plane \
  --i-understand-this-is-destructive
```

Instant 100 GiB memory spike on a worker:

```bash
./scripts/validate-node-pressure-eviction.sh \
  --node worker-1 \
  --mode memory-spike \
  --spike-memory-mib 102400 \
  --i-understand-this-is-destructive
```

`memory-spike` creates one BestEffort Pod that allocates and touches 102400 MiB
as fast as possible, in 1024 MiB chunks with no sleep between chunks. This mode
is more likely than the gradual memory test to trigger a container `OOMKilled`
result before kubelet can observe pressure and evict the Pod. The script still
requires kubelet eviction and a Ready node for success; a plain `OOMKilled`
result is reported as non-success.

Disk mode uses an `emptyDir` or container writable layer, never hostPath. If
`--max-disk-mib` is not provided, the script applies a 4096 MiB safety cap.

Admission controllers that inject memory limits can turn the memory test into a
container `OOMKilled` result instead of kubelet node-pressure eviction. The
script detects injected requests or limits and exits non-zero with an
inconclusive explanation when that happens.
