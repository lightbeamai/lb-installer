"""Core kubeadm operations: install, add/remove workers and edge nodes."""

import argparse
import logging
import os
from pathlib import Path

from common import Checkpoint, die
from image import resolve_image_for_deploy
from tf_mgr import TerraformManager, resolve_tf_script
from tfvars import (
    AwsEdgeTfVars, AwsTfVars, GcpEdgeTfVars, GcpTfVars,
    TfVarsLoader,
    resolve_tfvars_from_deployment_root,
)
from helpers import prompt
from deployment_mgr import deployment_type, edge_deployment_type, resolve_deployment

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Installer registry and loader
# ---------------------------------------------------------------------------

_INSTALLER_REGISTRY = {
    ("aws", "ctrl"): ("kubeadm/aws_hub_mgr.py", "AwsKubeadmInstaller"),
    ("gcp", "ctrl"): ("kubeadm/gcp_hub_mgr.py", "GcpKubeadmInstaller"),
    ("aws", "edge"): ("kubeadm/aws_edge_mgr.py", "AwsEdgeInstaller"),
    ("gcp", "edge"): ("kubeadm/gcp_edge_mgr.py", "GcpEdgeInstaller"),
}


def _get_installer_class(cloud: str, mode: str):
    """Load the CloudInstaller subclass for the given cloud/mode combination."""
    import importlib.util
    from common import die

    key = (cloud, mode)
    if key not in _INSTALLER_REGISTRY:
        die(f"Unsupported combination: cloud={cloud} mode={mode}")
    rel_path, class_name = _INSTALLER_REGISTRY[key]

    installer_root = Path(__file__).resolve().parent.parent  # orchestration/
    wrapper_path = installer_root / rel_path
    if not wrapper_path.is_file():
        die(f"Cloud wrapper not found: {wrapper_path}")

    module_name = f"lightbeam_{cloud}_{mode}_install"
    spec = importlib.util.spec_from_file_location(module_name, wrapper_path)
    if spec is None or spec.loader is None:
        die(f"Failed to load cloud wrapper module from {wrapper_path}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    cls = getattr(module, class_name, None)
    if cls is None:
        die(f"{class_name} not found in {wrapper_path}")
    return cls


def create_installer(args, cloud, mode, customer, ckpt, cloud_script_dir,
                     shared_scripts_dir, region="", project="", zone="",
                     worker_count=0, instance_count=0,
                     cp_ip="", cp_public_ip="",
                     wg_state_path=None):
    """Instantiate the correct CloudInstaller subclass for cloud+mode.

    All data from tfvars and terraform outputs is passed explicitly —
    the installer classes never read tfvars directly.
    """
    from common import die
    installer_cls = _get_installer_class(cloud, mode)
    common_kwargs = dict(
        args=args, cloud_script_dir=cloud_script_dir,
        shared_scripts_dir=shared_scripts_dir, customer=customer, ckpt=ckpt,
    )
    if cloud == "aws" and mode == "ctrl":
        return installer_cls(**common_kwargs, region=region,
                             worker_count=worker_count, cp_ip=cp_ip, cp_public_ip=cp_public_ip)
    elif cloud == "gcp" and mode == "ctrl":
        return installer_cls(**common_kwargs, project=project, zone=zone,
                             worker_count=worker_count, cp_ip=cp_ip, cp_public_ip=cp_public_ip)
    elif cloud == "gcp" and mode == "edge":
        return installer_cls(**common_kwargs, project=project, zone=zone,
                             instance_count=instance_count, wg_state_path=wg_state_path)
    elif cloud == "aws" and mode == "edge":
        return installer_cls(**common_kwargs, region=region,
                             instance_count=instance_count, wg_state_path=wg_state_path)
    else:
        die(f"Unsupported combination: cloud={cloud} mode={mode}")


# ---------------------------------------------------------------------------
# Remote checkpoint helpers
# ---------------------------------------------------------------------------

def clear_remote_checkpoints(
    args: argparse.Namespace,
    cloud: str,
    mode: str,
    customer: str,
    region: str = "",
) -> None:
    """Clear node-side checkpoints for a deployment."""
    dt = deployment_type(cloud, mode, region)
    tfvars_path = resolve_tfvars_from_deployment_root(customer, dt)

    if not tfvars_path.exists():
        log.warning("Cannot clear remote checkpoints; tfvars not found: %s", tfvars_path)
        return

    ckpt = Checkpoint(tfvars_path.parent / ".orchestration-state")
    installer_root = Path(__file__).resolve().parent.parent  # orchestration/
    cloud_script_dir = installer_root / "kubeadm"
    shared_scripts_dir = installer_root / "scripts" / "ctrl"
    region_val = region or TfVarsLoader.read_tfvars_value(tfvars_path, "region")
    project_val = TfVarsLoader.read_tfvars_value(tfvars_path, "project_id") if cloud == "gcp" else ""
    zone_val = TfVarsLoader.read_tfvars_value(tfvars_path, "zone") if cloud == "gcp" else ""
    worker_count = int(TfVarsLoader.read_tfvars_value(tfvars_path, "worker_node_count") or "0")
    instance_count = int(TfVarsLoader.read_tfvars_value(tfvars_path, "instance_count") or "0")

    try:
        installer = create_installer(
            args, cloud, mode, customer, ckpt,
            cloud_script_dir, shared_scripts_dir,
            region=region_val, project=project_val, zone=zone_val,
            worker_count=worker_count, instance_count=instance_count,
        )
        installer.clear_remote_checkpoints()
    except Exception as exc:
        log.warning("Could not clear remote checkpoints: %s", exc)


# ---------------------------------------------------------------------------
# Core install
# ---------------------------------------------------------------------------

def run_install(args: argparse.Namespace, cloud: str, mode: str, region: str = "") -> None:
    """Core install logic for a single cloud+mode combination.

    For edge deployments, *region* controls the deployment directory suffix:
    ``{cloud}-edge-{region}`` when region is set, ``{cloud}-edge`` otherwise.
    """
    dt = deployment_type(cloud, mode, region)
    args.deployment_type = dt

    requested_customer = (args.customer or os.getenv("LIGHTBEAM_CUSTOMER_NAME", "")).strip()
    tfvars_path = resolve_tfvars_from_deployment_root(requested_customer, dt)

    installer_root = Path(__file__).resolve().parent.parent  # orchestration/
    cloud_script_dir = installer_root / "kubeadm"
    if not cloud_script_dir.is_dir():
        die(f"Cloud script directory not found: {cloud_script_dir}")

    shared_scripts_dir = args.shared_scripts or (installer_root / "scripts" / "ctrl")
    if not shared_scripts_dir.is_dir():
        die(f"shared-scripts dir not found: {shared_scripts_dir}")

    tfvars_dir = tfvars_path.parent
    tfvars_dir.mkdir(parents=True, exist_ok=True)
    ckpt = Checkpoint(tfvars_dir / ".orchestration-state")
    customer = requested_customer

    if args.action == "init":
        ckpt.clear()
        log.info("Init action requested; cleared all checkpoints before terraform init.")

    done = ckpt.list_done()
    if done:
        log.info("Resuming - completed stages: %s", ", ".join(done))

    log.info("=== %s %s install ===", cloud.upper(), mode)
    log.info("  customer=%s  action=%s", customer, args.action)
    log.info("  tfvars=%s", tfvars_path)

    if args.reset:
        ckpt.clear(None if args.reset == "all" else args.reset)
        log.info("Checkpoint(s) cleared: %s", args.reset)
        if args.reset == "all":
            return

    # Clean up secrets and reservations on destroy
    if args.action == "destroy":
        if mode == "edge":
            from wireguard import EdgeWireguard

            wg_state_path = getattr(args, "wireguard_state", None) or (tfvars_dir / "wireguard.state")
            owner_prefix = f"{cloud}-edge"
            log.info("Releasing WireGuard address reservations...")
            EdgeWireguard.release_reservations(wg_state_path, owner_prefix)
        elif mode == "ctrl":
            from credentials import cleanup_ctrl_secrets

            log.info("Cleaning up control-plane secrets...")
            cleanup_ctrl_secrets(cloud, customer)

    # Run terraform actions (init, apply, destroy, output, cleanup-state)
    tf_script = resolve_tf_script(args, mode=mode)
    continue_install = TerraformManager.run_terraform_actions(
        args, ckpt, tf_script, customer,
        pre_apply_hook=lambda: resolve_image_for_deploy(args, cloud, tfvars_path),
    )
    if not continue_install:
        return

    # Parse tfvars (must exist after terraform init/apply)
    if not tfvars_path.is_file():
        die(f"terraform.tfvars not found after terraform stages: {tfvars_path}")

    tfvars = TfVarsLoader.load(tfvars_path, cloud, mode)
    customer = customer or tfvars.customer_name

    region = project = zone = ""
    worker_count = instance_count = 0
    cp_ip = cp_public_ip = ""
    if isinstance(tfvars, AwsTfVars):
        region = args.region or tfvars.region
        worker_count = tfvars.worker_node_count
    elif isinstance(tfvars, GcpTfVars):
        project = args.project or tfvars.project_id
        zone = args.zone or tfvars.zone
        worker_count = tfvars.worker_node_count
    elif isinstance(tfvars, GcpEdgeTfVars):
        project = args.project or tfvars.project_id
        zone = args.zone or tfvars.zone
        instance_count = tfvars.instance_count
    elif isinstance(tfvars, AwsEdgeTfVars):
        region = args.region or tfvars.region
        instance_count = tfvars.instance_count

    # Fetch terraform outputs for ctrl deployments
    if mode == "ctrl":
        from tfvars import get_cp_ip_from_terraform, get_cp_public_ip_from_terraform
        cp_ip = get_cp_ip_from_terraform(tfvars_dir)
        cp_public_ip = get_cp_public_ip_from_terraform(tfvars_dir)

    # Resolve wireguard state path for edge deployments
    wg_state_path = tfvars_dir / "wireguard.state" if mode == "edge" else None

    installer = create_installer(
        args, cloud, mode, customer, ckpt,
        cloud_script_dir, shared_scripts_dir,
        region=region, project=project, zone=zone,
        worker_count=worker_count, instance_count=instance_count,
        cp_ip=cp_ip, cp_public_ip=cp_public_ip,
        wg_state_path=wg_state_path,
    )
    installer.run()




# ---------------------------------------------------------------------------
# Worker/edge scaling
# ---------------------------------------------------------------------------

def add_ctrl_worker(args: argparse.Namespace, ctrl_cloud: str, customer: str) -> None:
    """Add worker nodes to an existing ctrl cluster."""
    deployment_type, tfvars_path = resolve_deployment(customer, ctrl_cloud, "ctrl")

    from cloud_config import get_ctrl_config
    cfg = get_ctrl_config(ctrl_cloud)

    tfvars = TfVarsLoader.load(tfvars_path, ctrl_cloud, "ctrl")
    if isinstance(tfvars, (AwsTfVars, GcpTfVars)):
        current_count = tfvars.worker_node_count
    else:
        die("Unsupported tfvars type for add-ctrl-worker.")
        return

    current_type = cfg.read(tfvars_path, "worker_type_key")
    current_root_disk = cfg.read(tfvars_path, "worker_disk_key")
    current_data_disk = cfg.read(tfvars_path, "worker_data_disk_key")

    log.info("Current worker configuration (from tfvars):")
    log.info("  Worker count:     %d", current_count)
    log.info("  Instance type:    %s", current_type)
    log.info("  Root disk (GB):   %s", current_root_disk)
    if current_data_disk:
        log.info("  Data disk (GB):   %s", current_data_disk)
    log.info("  Customer:         %s", customer)
    log.info("  Cloud:            %s", ctrl_cloud)
    log.info("")
    log.info("  Note: if a previous run updated tfvars but failed before terraform apply,")
    log.info("  enter the same count to retry the apply.")

    new_count_str = prompt(f"\nNew worker count (current in tfvars: {current_count}): ").strip()
    if not new_count_str:
        die("No worker count provided.")
    new_count = int(new_count_str)
    if new_count < 1:
        die("Worker count must be at least 1.")

    print(f"\nWorker configuration (press Enter to keep current):")
    new_type = prompt(f"  Instance type [{current_type}]: ").strip() or current_type
    new_root_disk = prompt(f"  Root disk GB [{current_root_disk}]: ").strip() or current_root_disk
    new_data_disk = ""
    if cfg.worker_data_disk_key:
        new_data_disk = prompt(f"  Data disk GB [{current_data_disk}]: ").strip() or current_data_disk

    adding = new_count - current_count

    print(f"\nSummary:")
    if adding > 0:
        new_workers = [f"{customer}-lightbeam-worker-{i + 1}" for i in range(current_count, new_count)]
        print(f"  Adding {adding} worker(s): {', '.join(new_workers)}")
    elif adding == 0:
        print(f"  Worker count unchanged ({new_count}) — will run terraform apply to sync state.")
    print(f"  Total workers:  {new_count}")
    print(f"  Instance type:  {new_type}")
    print(f"  Root disk:      {new_root_disk} GB")
    if new_data_disk:
        print(f"  Data disk:      {new_data_disk} GB")

    confirm = prompt("\nProceed? [y/N]: ").strip().lower()
    if confirm not in ("y", "yes"):
        log.info("Cancelled.")
        return

    log.info("Updating %s...", tfvars_path)
    TfVarsLoader.update_tfvars_value(tfvars_path, cfg.worker_count_key, str(new_count))
    TfVarsLoader.update_tfvars_value(tfvars_path, cfg.worker_type_key, f'"{new_type}"')
    TfVarsLoader.update_tfvars_value(tfvars_path, cfg.worker_disk_key, new_root_disk)
    if cfg.worker_data_disk_key and new_data_disk:
        TfVarsLoader.update_tfvars_value(tfvars_path, cfg.worker_data_disk_key, new_data_disk)

    # Resolve image before terraform apply so new workers use the published AMI
    args.deployment_type = dt
    resolve_image_for_deploy(args, ctrl_cloud, tfvars_path)

    # Terraform apply to create new instances
    from tf_mgr import terraform_apply
    tf_script = resolve_tf_script(args, mode="ctrl")
    if not tf_script:
        die("Cannot locate terraform.sh for ctrl deployment.")
    log.info("Running terraform apply to provision new worker(s)...")
    terraform_apply(tf_script, customer_name=customer)

    # Run install for the ctrl deployment (existing workers skipped via checkpoints)
    log.info("Installing new worker(s)...")
    args.skip_gateway = True
    args.skip_cp = True
    run_install(args, ctrl_cloud, "ctrl")


def remove_ctrl_worker(args: argparse.Namespace, ctrl_cloud: str, customer: str) -> None:
    """Remove worker nodes from an existing ctrl cluster."""
    deployment_type, tfvars_path = resolve_deployment(customer, ctrl_cloud, "ctrl")

    tfvars = TfVarsLoader.load(tfvars_path, ctrl_cloud, "ctrl")
    if isinstance(tfvars, (AwsTfVars, GcpTfVars)):
        current_count = tfvars.worker_node_count
    else:
        die("Unsupported tfvars type.")
        return

    log.info("Current worker count: %d", current_count)
    log.info("Customer: %s", customer)
    log.info("Cloud: %s", ctrl_cloud)

    # Show current workers
    all_workers = [f"{customer}-lightbeam-worker-{i + 1}" for i in range(current_count)]
    print("\nCurrent workers:")
    for i, name in enumerate(all_workers, 1):
        print(f"  {i}. {name}")

    new_count_str = prompt(f"\nNew worker count (current: {current_count}, min 0): ").strip()
    if not new_count_str:
        die("No worker count provided.")
    new_count = int(new_count_str)
    if new_count >= current_count:
        die(f"New count ({new_count}) must be less than current ({current_count}). Use --add worker to add.")
    if new_count < 0:
        die("Worker count cannot be negative.")

    removing = current_count - new_count
    removed_workers = [f"{customer}-lightbeam-worker-{i + 1}" for i in range(new_count, current_count)]

    print(f"\nWill remove {removing} worker(s):")
    for name in removed_workers:
        print(f"  - {name}")
    print(f"\nRemaining workers: {new_count}")

    confirm = prompt("\nProceed? This will drain and delete the nodes. [y/N]: ").strip().lower()
    if confirm not in ("y", "yes"):
        log.info("Cancelled.")
        return

    # Drain and delete nodes from Kubernetes before destroying instances
    try:
        from kubernetes import KubernetesCluster
        k8s = KubernetesCluster.from_tfvars(ctrl_cloud, customer, tfvars_path)
        k8s.drain_and_delete_workers(removed_workers)
    except SystemExit:
        log.warning("Could not connect to control plane — skipping K8s node cleanup.")
    except Exception as exc:
        log.warning("K8s node cleanup failed (non-fatal): %s", exc)

    # Update tfvars
    log.info("Updating worker_node_count to %d in %s...", new_count, tfvars_path)
    TfVarsLoader.update_tfvars_value(tfvars_path, "worker_node_count", str(new_count))

    # Terraform apply to destroy removed instances
    from tf_mgr import terraform_apply
    args.deployment_type = dt
    tf_script = resolve_tf_script(args, mode="ctrl")
    if not tf_script:
        die("Cannot locate terraform.sh for ctrl deployment.")
    log.info("Running terraform apply to remove worker(s)...")
    terraform_apply(tf_script, customer_name=customer)

    # Clean up checkpoints for removed workers
    ckpt_dir = tfvars_path.parent / ".orchestration-state"
    ckpt = Checkpoint(ckpt_dir)
    for name in removed_workers:
        ckpt_name = f"phase2_worker_{name}"
        if ckpt.is_done(ckpt_name):
            ckpt.clear(ckpt_name)
            log.info("Cleared checkpoint: %s", ckpt_name)

    log.info("Removed %d worker(s). Current count: %d", removing, new_count)


def add_edge_worker(args: argparse.Namespace, edge_cloud: str, customer: str, region: str = "") -> None:
    """Add edge worker nodes."""
    deployment_type, tfvars_path = resolve_deployment(customer, edge_cloud, "edge", region)

    from cloud_config import get_edge_config
    cfg = get_edge_config(edge_cloud)

    tfvars = TfVarsLoader.load(tfvars_path, edge_cloud, "edge")
    if isinstance(tfvars, (AwsEdgeTfVars, GcpEdgeTfVars)):
        current_count = tfvars.instance_count
    else:
        die("Unsupported tfvars type.")
        return

    current_type = cfg.read(tfvars_path, "type_key")

    log.info("Current edge configuration (from tfvars):")
    log.info("  Instance count:   %d", current_count)
    log.info("  Instance type:    %s", current_type)
    log.info("  Customer:         %s", customer)
    log.info("  Edge cloud:       %s", edge_cloud)
    log.info("")
    log.info("  Note: if a previous run updated tfvars but failed before terraform apply,")
    log.info("  enter the same count to retry the apply.")

    new_count_str = prompt(f"\nNew instance count (current in tfvars: {current_count}): ").strip()
    if not new_count_str:
        die("No instance count provided.")
    new_count = int(new_count_str)
    if new_count < 1:
        die("Instance count must be at least 1.")

    print(f"\nEdge worker configuration (press Enter to keep current):")
    new_type = prompt(f"  Instance type [{current_type}]: ").strip() or current_type

    adding = new_count - current_count

    print(f"\nSummary:")
    if adding > 0:
        new_workers = [f"{customer}-{edge_cloud}-edge-{i + 1}" for i in range(current_count, new_count)]
        print(f"  Adding {adding} edge worker(s): {', '.join(new_workers)}")
    elif adding == 0:
        print(f"  Instance count unchanged ({new_count}) — will run terraform apply to sync state.")
    print(f"  Total edge workers: {new_count}")
    print(f"  Instance type: {new_type}")

    confirm = prompt("\nProceed? [y/N]: ").strip().lower()
    if confirm not in ("y", "yes"):
        log.info("Cancelled.")
        return

    log.info("Updating %s...", tfvars_path)
    TfVarsLoader.update_tfvars_value(tfvars_path, cfg.count_key, str(new_count))
    TfVarsLoader.update_tfvars_value(tfvars_path, cfg.type_key, f'"{new_type}"')

    # Clear tf_apply so terraform re-applies with new instance count
    # WG expansion is handled automatically by expand_if_needed in the edge installer
    ckpt = Checkpoint(tfvars_path.parent / ".orchestration-state")
    ckpt.clear("tf_apply")
    log.info("Cleared tf_apply checkpoint for re-provisioning.")

    # Terraform apply + install
    log.info("Provisioning and installing new edge worker(s)...")
    run_install(args, edge_cloud, "edge", region=region)


def remove_edge_worker(args: argparse.Namespace, edge_cloud: str, customer: str, region: str = "") -> None:
    """Remove edge worker nodes."""
    deployment_type, tfvars_path = resolve_deployment(customer, edge_cloud, "edge", region)

    from tfvars import TfVarsLoader, AwsEdgeTfVars, GcpEdgeTfVars
    tfvars = TfVarsLoader.load(tfvars_path, edge_cloud, "edge")
    if isinstance(tfvars, (AwsEdgeTfVars, GcpEdgeTfVars)):
        current_count = tfvars.instance_count
    else:
        die("Unsupported tfvars type.")
        return

    log.info("Current edge instance count: %d", current_count)
    log.info("Customer: %s", customer)
    log.info("Edge cloud: %s", edge_cloud)

    all_workers = [f"{customer}-{edge_cloud}-edge-{i + 1}" for i in range(current_count)]
    print("\nCurrent edge workers:")
    for i, name in enumerate(all_workers, 1):
        print(f"  {i}. {name}")

    new_count_str = prompt(f"\nNew instance count (current: {current_count}, min 0): ").strip()
    if not new_count_str:
        die("No instance count provided.")
    new_count = int(new_count_str)
    if new_count >= current_count:
        die(f"New count ({new_count}) must be less than current ({current_count}). Use --add edge to add.")
    if new_count < 0:
        die("Instance count cannot be negative.")

    removing = current_count - new_count
    removed_workers = [f"{customer}-{edge_cloud}-edge-{i + 1}" for i in range(new_count, current_count)]

    print(f"\nWill remove {removing} edge worker(s):")
    for name in removed_workers:
        print(f"  - {name}")
    print(f"\nRemaining edge workers: {new_count}")

    confirm = prompt("\nProceed? This will delete the nodes. [y/N]: ").strip().lower()
    if confirm not in ("y", "yes"):
        log.info("Cancelled.")
        return

    # Drain and delete nodes from Kubernetes before destroying instances
    try:
        from kubernetes import KubernetesCluster
        ctrl_cloud = getattr(args, "ctrl_cloud", "") or _detect_ctrl_cloud(customer)
        ctrl_tfvars = resolve_tfvars_from_deployment_root(customer, f"{ctrl_cloud}-ctrl")
        k8s = KubernetesCluster.from_tfvars(ctrl_cloud, customer, ctrl_tfvars)
        k8s.drain_and_delete_workers(removed_workers)
    except SystemExit:
        log.warning("Could not connect to control plane — skipping K8s node cleanup.")
    except Exception as exc:
        log.warning("K8s node cleanup failed (non-fatal): %s", exc)

    # Update tfvars
    log.info("Updating instance_count to %d in %s...", new_count, tfvars_path)
    TfVarsLoader.update_tfvars_value(tfvars_path, "instance_count", str(new_count))

    # Terraform apply to destroy removed instances
    from tf_mgr import terraform_apply
    args.deployment_type = dt
    tf_script = resolve_tf_script(args, mode="edge")
    if not tf_script:
        die("Cannot locate terraform.sh for edge deployment.")
    log.info("Running terraform apply to remove edge worker(s)...")
    terraform_apply(tf_script, customer_name=customer)

    # Release WireGuard reservations for removed workers
    wg_state_path = tfvars_path.parent / "wireguard.state"
    if wg_state_path.exists():
        from wireguard import EdgeWireguard
        owner_prefix = f"{edge_cloud}-edge"
        log.info("Releasing WireGuard reservations for removed workers...")
        # Re-write wireguard.state with new count
        from wireguard import _parse_wireguard_state, _write_wireguard_state
        wg_state = _parse_wireguard_state(wg_state_path)
        remaining_addresses = wg_state.wireguard_addresses[:new_count]
        _write_wireguard_state(
            wg_state_path,
            wg_state.control_plane_customer_name,
            wg_state.control_plane_cloud,
            remaining_addresses,
        )
        log.info("Updated wireguard.state: %d addresses", len(remaining_addresses))

    # Clean up checkpoints for removed workers
    ckpt = Checkpoint(tfvars_path.parent / ".orchestration-state")
    for name in removed_workers:
        ckpt_name = f"phase2_edge_{name}"
        if ckpt.is_done(ckpt_name):
            ckpt.clear(ckpt_name)
            log.info("Cleared checkpoint: %s", ckpt_name)

    log.info("Removed %d edge worker(s). Current count: %d", removing, new_count)
