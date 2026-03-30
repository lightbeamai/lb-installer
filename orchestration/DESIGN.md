# Orchestration Design

## Scope
This document describes the architecture and execution flow of the `orchestration/` directory in `lb-installer`.

It covers:
- CLI and manager layers
- Terraform orchestration flow
- Node bootstrap flow
- State/checkpoint model
- Cloud abstraction points (AWS/GCP)
- How to extend the system safely

## Goals
- Provide a single operator CLI for `ctrl` and `edge` kubeadm deployments.
- Keep infra lifecycle (Terraform) and node lifecycle (bootstrap/install) orchestrated but separable.
- Support resumable execution after interruptions/failures.
- Keep cloud-specific details behind reusable transport wrappers.

## Non-Goals
- Re-implement Terraform logic in Python.
- Persist orchestration state in a database.
- Hide all cloud differences (some platform-specific behavior is expected).

## Directory Overview
High-level structure:

```text
orchestration/
  kubeadm_cli.py                # Main CLI entrypoint for deploy/install/destroy/scale
  deployment_mgr.py             # Deployment discovery, summaries, deployment typing
  image_mgr.py                  # Publish/list/delete pre-baked images
  kubeadm_cred_mgr.py           # Credential workflows
  kubeadm/
    kubernetes_cluster_mgr.py   # Core run_install + add/remove workers/edges
    aws_hub_mgr.py              # AWS ctrl installer
    gcp_hub_mgr.py              # GCP ctrl installer
    aws_edge_mgr.py             # AWS edge installer
    gcp_edge_mgr.py             # GCP edge installer
  lib/
    bootstrapper.py             # Node/installer abstract base classes
    tf_mgr.py                   # TerraformManager + terraform action orchestration
    tfvars.py                   # TfVarsLoader + tfvars parsers/resolvers
    aws.py                      # AWS transport nodes (SSM-based)
    gcp.py                      # GCP transport nodes (IAP SSH/SCP-based)
    credentials.py              # Control-plane credential and reservation retrieval
    image.py                    # Image lookup/selection logic
    helpers.py                  # Shared logging, prompt, spinner
    common.py                   # Checkpoint, constants, die()
  scripts/
    common/ ctrl/ edge/ node/ os/  # Remote scripts copied and executed on nodes
```

## Runtime Model

### 1) CLI Layer
`kubeadm_cli.py` parses user intent:
- action: `init | apply | install | destroy | cleanup-state | output | show | all`
- scope: `ctrl | edge | all`
- scaling operations: `--add/--remove worker|edge`

It then resolves target deployments and dispatches to:
- `kubeadm.kubernetes_cluster_mgr.run_install(...)` for install-like actions
- `add_*`/`remove_*` helpers for scaling
- deployment discovery/summary helpers in `deployment_mgr.py`

### 2) Deployment Resolution Layer
`deployment_mgr.py` normalizes deployment identity:
- `deployment_type = <cloud>-ctrl | <cloud>-edge[-<region>]`
- deployment state path:
  - `${LIGHTBEAM_DEPLOYMENT_ROOT}/${customer}_${deployment_type}/terraform.tfvars`

It also handles:
- auto-detection of ctrl cloud
- discovery of edge deployments
- human-readable status summaries from checkpoint files

### 3) Terraform Lifecycle Layer
`lib/tf_mgr.py` (`TerraformManager`) handles Terraform wrapper execution:
- `run_terraform_sh(...)`
- `terraform_init/apply/destroy/cleanup-state/setup(...)`
- direct `terraform output` reads

`run_terraform_actions(...)` (invoked by `kubernetes_cluster_mgr.py`) is the orchestrated gate:
- runs requested Terraform phases
- marks checkpoints (`tf_init`, `tf_apply`, etc.)
- decides whether install phase should continue

### 4) Install Lifecycle Layer
`kubeadm/kubernetes_cluster_mgr.py` orchestrates install for a specific `(cloud, mode)`:
1. Resolve tfvars + deployment dir
2. Execute Terraform action path (via `TerraformManager`)
3. Load typed tfvars (`TfVarsLoader`)
4. Build installer from registry:
   - `("aws","ctrl") -> AwsKubeadmInstaller`
   - `("gcp","ctrl") -> GcpKubeadmInstaller`
   - `("aws","edge") -> AwsEdgeInstaller`
   - `("gcp","edge") -> GcpEdgeInstaller`
5. Run installer

### 5) Node Bootstrap Lifecycle
`lib/bootstrapper.py` defines the core template:
- `wait() -> prepare() -> launch() -> monitor()`

Cloud-specific node classes in `lib/aws.py` and `lib/gcp.py` implement transport primitives:
- AWS: SSM send-command / polling
- GCP: IAP SSH/SCP

Role-specific abstractions:
- `ControllerNode`
- `WorkerNode`
- `GatewayNode`
- `EdgeNode`

These provide idempotent stage behavior with remote node markers.

## State and Idempotency

### Local Checkpoints
`common.Checkpoint` stores local stage markers under:
- `${deployment_state_dir}/.orchestration-state/*.done`

Used to:
- resume interrupted runs
- skip completed phases
- invalidate stale checkpoints when image metadata changes

### Remote Node Checkpoints
Remote markers live at:
- `/var/lib/lightbeam/orchestration-state/*.done`

Used to avoid rerunning expensive node-side steps (package installs, launch scripts).

### Bootstrap Artifacts on Nodes
Remote bootstrap directory:
- `/var/lib/lightbeam/bootstrap`

Typical logs:
- control-plane: `/root/master-install.log`
- worker/edge: `/root/worker-install.log` or `/root/worker-bootstrap.log`
- gateway: `/root/gateway-*.log`

## Cloud Abstraction Boundaries

### AWS (`lib/aws.py`)
- Node lookup via EC2 tags
- Transport via SSM
- Credentials/auth error interpretation
- Node operations: deploy bundle, run scripts, poll command status

### GCP (`lib/gcp.py`)
- Transport via `gcloud compute ssh/scp --tunnel-through-iap`
- Retry and wait logic around IAP connectivity
- Node operations parallel to AWS interface

### Why this split matters
Installer logic (`kubernetes_cluster_mgr` + cloud installers) should remain cloud-agnostic and call node abstractions, not direct `aws`/`gcloud` shell commands.

## Credentials and Control-Plane Data
`lib/credentials.py` handles fetching:
- WireGuard public key / endpoint
- udp2raw password
- kubeadm join command
- CA certificate
- WireGuard client config data and reservations

Data source strategy:
- prefer live control-plane queries when possible
- fallback to cloud secret stores when needed

## Typical End-to-End Flows

### `--action all` (ctrl/edge)
1. CLI parses and resolves deployments
2. Terraform init/apply via `TerraformManager`
3. tfvars loaded and installer selected
4. node bootstrap runs in role order
5. checkpoints written locally/remotely

### `--action destroy`
1. Optional cleanup hooks (e.g., credential/reservation cleanup)
2. Terraform destroy via wrapper
3. local state may be cleaned separately with `cleanup-state`

### `--add worker` / `--add edge`
1. Read current tfvars
2. Prompt new target count/config
3. Update tfvars
4. Apply Terraform
5. Bootstrap only newly added nodes

## Extension Guide

### Add a new cloud or mode
1. Implement transport node(s) in `lib/<cloud>.py` following `BootstrapNode` contracts.
2. Implement cloud installer wrapper in `kubeadm/<cloud>_<mode>_mgr.py`.
3. Register in `_INSTALLER_REGISTRY` (`kubeadm/kubernetes_cluster_mgr.py`).
4. Add tfvars dataclass/parser in `tfvars.py` if schema differs.
5. Add/adjust remote scripts under `scripts/`.

### Add a new orchestrated phase
1. Define clear checkpoint names (local + optional remote).
2. Make phase idempotent.
3. Integrate phase in appropriate installer `run()` path.
4. Ensure failure mode is explicit and recoverable.

## Operational Invariants
- Deployment identity is always `${customer}_${deployment_type}`.
- Terraform state for a deployment is co-located with its `terraform.tfvars`.
- Orchestration is resumable by default; avoid destructive side effects in non-destroy actions.
- Node bootstrap scripts are treated as source of truth for host configuration steps.

## Known Design Tradeoffs
- Wrapper-heavy architecture improves operability and resume behavior but increases cross-file navigation overhead.
- Some logic still exists in both Python and shell layers by design (Python orchestrates; shell executes host setup).
- Cloud parity is high but not total; provider-specific behavior remains where unavoidable.

## Quick Debug Pointers
- CLI resolution/dispatch issues: `kubeadm_cli.py`, `deployment_mgr.py`
- Terraform command path issues: `lib/tf_mgr.py`
- tfvars parsing/path issues: `lib/tfvars.py`
- Node transport issues: `lib/aws.py`, `lib/gcp.py`
- Bootstrap phase failures: `kubeadm/*_mgr.py` + node logs in `/root/*.log`
