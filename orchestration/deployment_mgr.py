"""Deployment management for Lightbeam kubeadm clusters.

Provides KubeadmDeployment class and discovery functions.
Designed to be extended with other deployment types in the future.
"""

import argparse
import logging
import os
import subprocess
from pathlib import Path

from common import Checkpoint, die
from tfvars import TfVarsLoader, resolve_tfvars_from_deployment_root
from helpers import prompt

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Static helpers
# ---------------------------------------------------------------------------

def deployment_type(cloud: str, mode: str, region: str = "") -> str:
    """Build deployment type string: 'aws-ctrl', 'aws-edge', 'aws-edge-us-east-1'."""
    if mode == "edge" and region:
        return f"{cloud}-edge-{region}"
    return f"{cloud}-{mode}"


def edge_deployment_type(cloud: str, region: str) -> str:
    """Build edge deployment type string."""
    return deployment_type(cloud, "edge", region)


def edge_cloud_from_deployment_type(dt: str) -> tuple:
    """Extract (cloud, region) from deployment type like 'aws-edge-us-east-1'."""
    for cloud in ("aws", "gcp"):
        prefix = f"{cloud}-edge"
        if dt == prefix:
            return cloud, ""
        if dt.startswith(prefix + "-"):
            return cloud, dt[len(prefix) + 1:]
    return "", ""


def parse_edge_cloud_spec(spec: str) -> tuple:
    """Parse 'aws:us-east-1' or 'aws' into (cloud, region)."""
    if ":" in spec:
        cloud, region = spec.split(":", 1)
    else:
        cloud, region = spec, ""
    cloud = cloud.strip().lower()
    region = region.strip().lower()
    if cloud not in ("aws", "gcp"):
        die(f"Invalid edge cloud: {cloud}. Must be aws or gcp.")
    return cloud, region


def discover_edge_deployments(customer: str) -> list:
    """Find existing edge deployment directories for a customer.

    Returns list of (cloud, region, deployment_type) tuples.
    Supports both legacy (aws-edge) and regional (aws-edge-us-east-1) dirs.
    """
    deployment_root = os.getenv("LIGHTBEAM_DEPLOYMENT_ROOT", "").strip()
    if not deployment_root:
        return []
    root_path = Path(deployment_root).expanduser()
    results = []
    for entry in sorted(root_path.iterdir()):
        if not entry.is_dir() or not (entry / "terraform.tfvars").exists():
            continue
        name = entry.name
        prefix = f"{customer}_"
        if not name.startswith(prefix):
            continue
        suffix = name[len(prefix):]
        for cloud in ("aws", "gcp"):
            edge_prefix = f"{cloud}-edge"
            if suffix == edge_prefix or suffix.startswith(edge_prefix + "-"):
                cloud_found, region = edge_cloud_from_deployment_type(suffix)
                if cloud_found:
                    results.append((cloud_found, region, suffix))
    return results



def resolve_deployment(customer: str, cloud: str, mode: str, region: str = "") -> tuple:
    """Resolve deployment type and tfvars path. Returns (deployment_type, tfvars_path).

    Dies if tfvars file does not exist.
    """
    dt = deployment_type(cloud, mode, region)
    tfvars_path = resolve_tfvars_from_deployment_root(customer, dt)
    if not tfvars_path.exists():
        die(f"No {dt} deployment found for '{customer}': {tfvars_path}")
    return dt, tfvars_path



def detect_ctrl_cloud(customer: str) -> str:
    """Auto-detect the ctrl cloud from existing deployment directories.

    Returns the cloud name if exactly one ctrl deployment exists for the
    customer, otherwise dies with a helpful error.
    """
    deployment_root = os.getenv("LIGHTBEAM_DEPLOYMENT_ROOT", "").strip()
    if not deployment_root:
        die("LIGHTBEAM_DEPLOYMENT_ROOT is not set. Cannot auto-detect cloud.")
    root_path = Path(deployment_root).expanduser()
    found = []
    for cloud in ("aws", "gcp"):
        ctrl_dir = root_path / f"{customer}_{cloud}-ctrl"
        if ctrl_dir.is_dir() and (ctrl_dir / "terraform.tfvars").exists():
            found.append(cloud)
    if len(found) == 1:
        return found[0]
    if len(found) == 0:
        die(f"No ctrl deployment found for customer '{customer}'. Pass --ctrl-cloud explicitly.")
    die(f"Multiple ctrl deployments found for '{customer}': {', '.join(found)}. Pass --ctrl-cloud explicitly.")
    return ""  # unreachable




# ---------------------------------------------------------------------------
# KubeadmDeployment class
# ---------------------------------------------------------------------------

class KubeadmDeployment:
    """Represents a single kubeadm deployment (ctrl or edge)."""

    def __init__(self, customer: str, cloud: str, mode: str, region: str = ""):
        self.customer = customer
        self.cloud = cloud
        self.mode = mode
        self.region = region
        self.dt = deployment_type(cloud, mode, region)
        self.tfvars_path = resolve_tfvars_from_deployment_root(customer, self.dt)
        self.tfvars_dir = self.tfvars_path.parent

    @property
    def label(self) -> str:
        return self.dt

    def status(self) -> str:
        """Deployment status from checkpoints."""
        try:
            ckpt = Checkpoint(self.tfvars_dir / ".orchestration-state")
            done = ckpt.list_done()
            if not done:
                return "fresh — will deploy from scratch"
            if self.mode == "ctrl":
                has_tf = "tf_init" in done and "tf_apply" in done
                has_cp = "phase1_cp" in done
                has_cluster = "phase3_cluster_ready" in done
                if has_tf and has_cp and has_cluster:
                    return "all phases complete — no changes expected"
                if not has_tf:
                    return "partially complete — will resume from terraform"
                if not has_cp:
                    return "partially complete — will resume from control plane setup"
                return "partially complete — will resume from worker setup"
            else:
                has_tf = "tf_init" in done and "tf_apply" in done
                phase2 = [d for d in done if d.startswith("phase2_edge_")]
                phase1 = [d for d in done if d.startswith("phase1_packages_")]
                if has_tf and phase2:
                    return "all phases complete — no changes expected"
                if has_tf and phase1:
                    return "packages installed — will resume from VPN + join"
                if has_tf:
                    return "infra provisioned — will resume from install"
                return "partially complete — will resume"
        except Exception:
            return ""

    def print_summary(self):
        """Print infrastructure summary."""
        if self.mode == "ctrl":
            self._print_ctrl_summary()
        else:
            self._print_edge_summary()

    def _print_ctrl_summary(self):
        from cloud_config import get_ctrl_config
        try:
            if not self.tfvars_path.exists():
                return
            cfg = get_ctrl_config(self.cloud)
            status = self.status()
            status_str = f"    [{status}]" if status else ""
            log.info("")
            log.info("  Infrastructure summary (%s):%s", self.dt, status_str)
            if cfg.has_gateway:
                log.info("    Gateway:  %s, %s GB disk", cfg.gateway_instance_type, cfg.gateway_disk_gb)
            else:
                log.info("    Gateway:  None")
            cp_type = cfg.read(self.tfvars_path, "cp_type_key")
            cp_disk_str = cfg.disk_summary(self.tfvars_path, "cp")
            log.info("    Ctrl:     %s, %s", cp_type, cp_disk_str)
            w_count = cfg.read(self.tfvars_path, "worker_count_key") or "3"
            w_type = cfg.read(self.tfvars_path, "worker_type_key")
            w_disk_str = cfg.disk_summary(self.tfvars_path, "worker")
            log.info("    Workers:  %s x %s, %s", w_count, w_type, w_disk_str)
        except Exception:
            pass

    def _print_edge_summary(self):
        from cloud_config import get_edge_config
        try:
            if not self.tfvars_path.exists():
                return
            cfg = get_edge_config(self.cloud)
            status = self.status()
            status_str = f"    [{status}]" if status else ""
            log.info("")
            log.info("  Infrastructure summary (%s):%s", self.label, status_str)
            count = cfg.read(self.tfvars_path, "count_key") or "1"
            inst_type = cfg.read(self.tfvars_path, "type_key")
            disk = cfg.read(self.tfvars_path, "disk_key")
            log.info("    Edge nodes: %s x %s, %s GB disk", count, inst_type, disk)
        except Exception:
            pass

    def print_image_summary(self):
        """Print image resolution info."""
        try:
            if not self.tfvars_path.exists():
                return
            for name in ("botocore.credentials", "botocore.utils", "boto3.resources.action"):
                logging.getLogger(name).setLevel(logging.WARNING)
            from image import ImageManager
            region_val = TfVarsLoader.read_tfvars_value(self.tfvars_path, "region")
            project_val = TfVarsLoader.read_tfvars_value(self.tfvars_path, "project_id") if self.cloud == "gcp" else ""
            zone_val = TfVarsLoader.read_tfvars_value(self.tfvars_path, "zone") if self.cloud == "gcp" else ""
            kwargs = {"region": region_val} if self.cloud == "aws" else {"project": project_val, "zone": zone_val}
            mgr = ImageManager.create(self.cloud, **kwargs)
            current_custom = TfVarsLoader.read_tfvars_value(self.tfvars_path, mgr.tfvars_key())
            latest = None
            try:
                latest = mgr.find_latest()
            except Exception:
                pass
            if current_custom:
                if latest and latest.id == current_custom:
                    log.info("    Image:    %s (%s) — latest published", latest.name, latest.id)
                    log.info("              Package installation will be skipped.")
                elif latest:
                    log.info("    Image:    %s (tfvars) — newer available: %s (%s)", current_custom, latest.name, latest.id)
                    log.info("              You will be prompted to confirm the upgrade.")
                else:
                    log.info("    Image:    %s (from tfvars)", current_custom)
                    log.info("              Package installation will be skipped.")
            elif latest:
                log.info("    Image:    %s (%s) — published image available", latest.name, latest.id)
                log.info("              Will be used; package installation will be skipped.")
            else:
                log.info("    Image:    Default OS (no published image found)")
                log.info("              Packages will be installed from scratch.")
        except Exception:
            pass

    def show_output(self):
        """Run terraform output."""
        if not self.tfvars_path.exists():
            return
        state_file = self.tfvars_dir / "terraform.tfstate"
        state_dir = self.tfvars_dir / ".terraform"
        if not state_file.exists() and not state_dir.exists():
            return
        log.info("=== %s %s output (%s) ===", self.cloud.upper(), self.mode, self.customer)
        result = subprocess.run(
            ["terraform", "output"], cwd=str(self.tfvars_dir),
            capture_output=True, text=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            print(result.stdout)

    @classmethod
    def discover_edge(cls, customer):
        """Find existing edge deployments for a customer."""
        results = []
        deployment_root = os.getenv("LIGHTBEAM_DEPLOYMENT_ROOT", "").strip()
        if not deployment_root:
            return results
        root_path = Path(deployment_root).expanduser()
        for entry in sorted(root_path.iterdir()):
            if not entry.is_dir() or not (entry / "terraform.tfvars").exists():
                continue
            name = entry.name
            prefix = f"{customer}_"
            if not name.startswith(prefix):
                continue
            suffix = name[len(prefix):]
            for cloud in ("aws", "gcp"):
                edge_prefix = f"{cloud}-edge"
                if suffix == edge_prefix or suffix.startswith(edge_prefix + "-"):
                    cloud_found, region = edge_cloud_from_deployment_type(suffix)
                    if cloud_found:
                        results.append(cls(customer, cloud_found, "edge", region))
        return results

    @classmethod
    def discover_all(cls, customer=""):
        """Find all deployment directories."""
        deployment_root = os.getenv("LIGHTBEAM_DEPLOYMENT_ROOT", "").strip()
        if not deployment_root:
            die("LIGHTBEAM_DEPLOYMENT_ROOT is not set.")
        root_path = Path(deployment_root).expanduser()
        if not root_path.is_dir():
            return []
        results = []
        for entry in sorted(root_path.iterdir()):
            if not entry.is_dir() or not (entry / "terraform.tfvars").exists():
                continue
            name = entry.name
            for cloud in ("aws", "gcp"):
                ctrl_suffix = f"_{cloud}-ctrl"
                if name.endswith(ctrl_suffix):
                    cust = name[:-len(ctrl_suffix)]
                    if not customer or cust == customer:
                        results.append(cls(cust, cloud, "ctrl"))
                    continue
                edge_prefix = f"_{cloud}-edge"
                idx = name.find(edge_prefix)
                if idx > 0:
                    cust = name[:idx]
                    dt = name[idx + 1:]
                    c, r = edge_cloud_from_deployment_type(dt)
                    if c and (not customer or cust == customer):
                        results.append(cls(cust, c, "edge", r))
        return results


# ---------------------------------------------------------------------------
# Free functions
# ---------------------------------------------------------------------------

def print_full_summary(action_label, deployments):
    """Print deployment targets and infrastructure summary."""
    log.info("%s:", action_label)
    for d in deployments:
        log.info("  - %s (%s)", d.dt, d.customer)
    for d in deployments:
        d.print_summary()
        d.print_image_summary()


def show_deployments(customer=""):
    """Print all configured deployments with status."""
    deployments = KubeadmDeployment.discover_all(customer)
    if not deployments:
        label = f" for customer '{customer}'" if customer else ""
        log.info("No deployments found%s.", label)
        return
    log.info("Configured deployments:")
    current_cust = ""
    for d in deployments:
        if d.customer != current_cust:
            current_cust = d.customer
            print(f"\n  Customer: {d.customer}")
        status = d.status()
        status_str = f"  [{status}]" if status else ""
        print(f"    {d.dt:<25s}  {d.tfvars_dir}{status_str}")
