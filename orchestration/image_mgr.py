#!/usr/bin/env python3
"""Standalone image management: publish, list, and delete pre-baked edge images.

For publishing, creates a temporary edge node (customer=publish-XX), installs
packages, snapshots the image, and optionally destroys the instance.

Usage:
    # Publish a new image
    python image_manager.py --cloud aws --action publish

    # Publish and keep the instance for debugging
    python image_manager.py --cloud aws --action publish --keep-instance

    # List published images
    python image_manager.py --cloud aws --action list

    # Delete images matching a pattern
    python image_manager.py --cloud aws --action delete --pattern "ubuntu.*2026"

    # Delete all published images
    python image_manager.py --cloud aws --action delete --pattern "*"
"""

import argparse
import logging
import os
import random
import subprocess
import sys
from pathlib import Path

# Resolve import paths
_repo_root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
sys.path.insert(0, str(_repo_root / "orchestration" / "lib"))
sys.path.insert(0, str(_repo_root / "orchestration"))

from common import Checkpoint, die, resolve_customer_name
from image import ImageManager
from cloud_config import get_edge_config
from tf_mgr import resolve_tf_script
from tfvars import (
    TfVarsLoader,
    AwsEdgeTfVars,
    GcpEdgeTfVars,
    resolve_tfvars_from_deployment_root,
)

logging.basicConfig(
    format="[%(asctime)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

# Suppress noisy boto credential messages
for _name in ("botocore.credentials", "botocore.utils", "boto3.resources.action"):
    logging.getLogger(_name).setLevel(logging.WARNING)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Manage pre-baked Lightbeam edge images (AMI/GCP).",
    )
    parser.add_argument(
        "--cloud",
        choices=["aws", "gcp"],
        required=True,
        help="Cloud provider.",
    )
    parser.add_argument(
        "--action",
        choices=["publish", "list", "delete"],
        required=True,
        help="Action: publish (create image), list (show images), delete (remove images).",
    )
    parser.add_argument(
        "--pattern",
        help="Regex pattern for delete action. Use '*' for all.",
    )
    parser.add_argument(
        "--keep-instance",
        action="store_true",
        help="Do not destroy the publish instance after image creation (for debugging).",
    )
    parser.add_argument(
        "--region",
        help="AWS region (default: auto-detect or us-east-1).",
    )
    parser.add_argument(
        "--project",
        help="GCP project ID (required for GCP).",
    )
    parser.add_argument(
        "--zone",
        help="GCP zone (required for GCP publish).",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=1800,
        help="Timeout for remote operations in seconds (default: 1800).",
    )
    parser.add_argument(
        "--v",
        action="store_true",
        help="Verbose output.",
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _read_tfvars_value(tfvars_path: Path, key: str) -> str:
    if not tfvars_path.exists():
        return ""
    for line in tfvars_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        if k.strip() == key:
            return v.strip().strip('"').strip("'")
    return ""


def _update_tfvars_value(tfvars_path: Path, key: str, value: str) -> None:
    import re
    content = tfvars_path.read_text()
    pattern = rf'({re.escape(key)}\s*=\s*).*'
    if re.search(pattern, content):
        content = re.sub(pattern, f'\\g<1>{value}', content)
    else:
        content = content.rstrip() + f"\n{key} = {value}\n"
    tfvars_path.write_text(content)


def _generate_publish_customer() -> str:
    """Generate a unique customer name for publish: publish-XX."""
    ctr = random.randint(10, 99)
    return f"publish-{ctr}"


def _get_image_manager(cloud: str, region: str = "", project: str = "", zone: str = "") -> ImageManager:
    """Create an ImageManager from explicit params."""
    if cloud == "aws":
        return ImageManager.create("aws", region=region or "us-east-1")
    elif cloud == "gcp":
        if not project:
            die("--project is required for GCP.")
        return ImageManager.create("gcp", project=project, zone=zone or "")
    else:
        die(f"Unsupported cloud: {cloud}")


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

def _action_list(args: argparse.Namespace) -> None:
    """List published images."""
    mgr = ImageManager.create_for_query(
        args.cloud,
        region=args.region or "",
        project=args.project or "",
    )
    mgr.print_list()


def _action_delete(args: argparse.Namespace) -> None:
    """Delete images matching a pattern."""
    if not args.pattern:
        die("--pattern is required for delete (use '*' for all).")
    mgr = ImageManager.create_for_query(
        args.cloud,
        region=args.region or "",
        project=args.project or "",
    )
    mgr.delete_matching(args.pattern)


def _action_publish(args: argparse.Namespace) -> None:
    """Create a temporary edge node, install packages, and publish the image."""
    cloud = args.cloud
    region = args.region or ""
    project = args.project or ""
    zone = args.zone or ""

    # Validate cloud-specific requirements
    if cloud == "aws" and not region:
        region = "us-east-1"
        log.info("No --region specified, defaulting to %s.", region)
    if cloud == "gcp":
        if not project:
            import subprocess as _sp
            try:
                r = _sp.run(["gcloud", "config", "get-value", "project"],
                            capture_output=True, text=True, timeout=10)
                project = r.stdout.strip()
            except Exception:
                pass
            if not project:
                die("--project is required for GCP publish (or set a default gcloud project).")
            log.info("Using gcloud default project: %s", project)
        if not zone:
            import subprocess as _sp2
            try:
                r = _sp2.run(["gcloud", "config", "get-value", "compute/zone"],
                             capture_output=True, text=True, timeout=10)
                zone = r.stdout.strip()
            except Exception:
                pass
            if not zone:
                die("--zone is required for GCP publish (or set a default gcloud zone).")
            log.info("Using gcloud default zone: %s", zone)

    # Generate unique customer name for the publish deployment
    customer = _generate_publish_customer()
    deployment_type = f"{cloud}-edge"
    edge_cfg = get_edge_config(cloud)

    log.info("=== Image Publish ===")
    log.info("  Cloud:    %s", cloud)
    log.info("  Customer: %s (temporary)", customer)
    if cloud == "aws":
        log.info("  Region:   %s", region)
    else:
        log.info("  Project:  %s", project)
        log.info("  Zone:     %s", zone)

    # Resolve tfvars path — create deployment dir
    tfvars_path = resolve_tfvars_from_deployment_root(customer, deployment_type)
    tfvars_dir = tfvars_path.parent
    tfvars_dir.mkdir(parents=True, exist_ok=True)

    # Create a minimal args namespace for _run_install compatibility
    install_args = argparse.Namespace(
        customer=customer,
        ctrl_cloud="",
        edge_cloud=[cloud],
        action="all",
        install_only=True,
        no_published_image=True,
        skip_packages=False,
        skip_gateway=False,
        skip_cp=False,
        skip_workers=False,
        timeout=args.timeout,
        v=args.v,
        terraform_script=None,
        shared_scripts=None,
        wireguard_state=None,
        has_gateway=None,
        reset=None,
        region=region,
        project=project,
        zone=zone,
        scope=None,
        target=None,
        deployment_type=deployment_type,
        image=None,
    )

    # Write initial tfvars with publish overrides (small disk, 1 instance, no custom image)
    if cloud == "aws":
        tfvars_content = (
            f'customer_name = "{customer}"\n'
            f'region = "{region}"\n'
            f'availability_zone = "{region}a"\n'
            f'instance_count = 1\n'
            f'instance_type = "{edge_cfg.type_default}"\n'
            f'{edge_cfg.disk_key} = 10\n'
            f'os_type = "ubuntu"\n'
            f'custom_ami = ""\n'
        )
    else:  # gcp
        tfvars_content = (
            f'customer_name = "{customer}"\n'
            f'project_id = "{project}"\n'
            f'region = "{zone[:-2]}"\n'
            f'zone = "{zone}"\n'
            f'instance_count = 1\n'
            f'machine_type = "{edge_cfg.type_default}"\n'
            f'{edge_cfg.disk_key} = 10\n'
            f'os_type = "ubuntu"\n'
            f'custom_image = ""\n'
        )
    tfvars_path.write_text(tfvars_content)
    log.info("Created tfvars: %s", tfvars_path)
    log.info("  Disk size: 10 GB (minimal for publish)")
    log.info("  Image: default OS (no published image)")

    # Clear any stale checkpoints
    ckpt = Checkpoint(tfvars_dir / ".orchestration-state")
    ckpt.clear()

    # No setup needed — LIGHTBEAM_NO_SYMLINKS=1 is set by terraform.py,
    # so terraform reads directly from deployment dir without symlinks.

    # Import and run the install
    from kubeadm.kubernetes_cluster_mgr import run_install as _run_install
    try:
        _run_install(install_args, cloud, "edge", region="" if cloud == "aws" else "")
    except SystemExit:
        die("Install failed. Check logs above.")

    # Resolve instance for image creation
    mgr = _get_image_manager(cloud, region=region, project=project, zone=zone)
    tfvars = TfVarsLoader.load(tfvars_path, cloud, "edge")

    if isinstance(tfvars, AwsEdgeTfVars):
        effective_region = region or tfvars.region
        instance_name = f"{customer}-aws-edge-{effective_region}-1"
        from aws import AwsNode, AwsEdgeNode
        instance_id = AwsNode.get_instance_id(instance_name, effective_region)
    elif isinstance(tfvars, GcpEdgeTfVars):
        instance_name = f"{customer}-gcp-edge-{tfvars.zone}-1"
        instance_id = instance_name
        from gcp import GcpEdgeNode
    else:
        die(f"Unsupported cloud: {cloud}")
        return

    # Generate image name
    image_name = mgr.generate_image_name(instance_id)
    log.info("Generated image name: %s", image_name)

    print(f"\nPublishing image from: {instance_id}")
    print(f"  Image name: {image_name}")
    confirm = input("\nProceed with publish? [y/N]: ").strip().lower()
    if confirm not in ("y", "yes"):
        log.info("Cancelled.")
        if not args.keep_instance:
            _destroy_publish_instance(install_args, cloud, customer)
        return

    # Clean up instance before snapshotting
    if isinstance(tfvars, AwsEdgeTfVars):
        node = AwsEdgeNode(instance_id=instance_id, display_name=instance_name,
                           region=effective_region, timeout=60,
                           tarball_bytes=b"", env_config="")
    elif isinstance(tfvars, GcpEdgeTfVars):
        node = GcpEdgeNode(project=tfvars.project_id, zone=tfvars.zone,
                           timeout=60, instance=instance_id,
                           tarball_bytes=b"", env_config="")
    else:
        node = None

    if node:
        node.cleanup_for_publish()

    # Create the image
    img = mgr.rotate_and_create(instance_id, image_name, f"Lightbeam edge image from {instance_id}")
    log.info("Image published: %s (%s)", img.name, img.id)

    # Destroy the publish instance unless --keep-instance
    if not args.keep_instance:
        _destroy_publish_instance(install_args, cloud, customer)
    else:
        log.info("Instance kept (--keep-instance). To destroy later:")
        log.info("  python image_manager.py --cloud %s --action publish --keep-instance", cloud)
        log.info("  Or manually: terraform destroy in %s", tfvars_dir)


def _destroy_publish_instance(args: argparse.Namespace, cloud: str, customer: str) -> None:
    """Destroy the temporary publish instance and remove deployment directory."""
    import shutil
    from tf_mgr import terraform_destroy

    log.info("Destroying temporary publish instance...")
    args.action = "destroy"
    tf_script = resolve_tf_script(args, mode="edge")
    if not tf_script:
        log.warning("Cannot locate terraform.sh — manual cleanup may be needed.")
        return

    try:
        terraform_destroy(tf_script, customer_name=customer)
    except SystemExit:
        log.warning("Terraform destroy failed. Manual cleanup may be needed.")

    # No symlinks to clean — just remove the deployment directory
    deployment_type = f"{cloud}-edge"
    tfvars_path = resolve_tfvars_from_deployment_root(customer, deployment_type)
    tfvars_dir = tfvars_path.parent
    if tfvars_dir.is_dir():
        shutil.rmtree(tfvars_dir, ignore_errors=True)
        log.info("Removed deployment directory: %s", tfvars_dir)

    log.info("Publish instance destroyed and cleaned up.")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    args = parse_args()

    if args.action == "list":
        _action_list(args)
    elif args.action == "delete":
        _action_delete(args)
    elif args.action == "publish":
        _action_publish(args)


if __name__ == "__main__":
    main()
