#!/usr/bin/env python3
"""AWS Edge Node installer — concrete CloudInstaller for edge nodes on AWS."""

from __future__ import annotations

import argparse
import logging
import subprocess
import sys
from pathlib import Path
from typing import Optional

# Resolve import paths relative to the git repository root
_repo_root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
sys.path.insert(0, str(_repo_root / "orchestration" / "lib"))
sys.path.insert(0, str(_repo_root / "orchestration"))

from bootstrapper import EdgeInstaller
from bootstrapper import run_parallel
from common import Checkpoint, die
from wireguard import EdgeWireguard
from aws import AwsEdgeNode, AwsNode

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Concrete installer class
# ---------------------------------------------------------------------------


class AwsEdgeInstaller(EdgeInstaller):
    """Installs edge nodes on AWS via SSM."""

    def __init__(
        self,
        args: argparse.Namespace,
        cloud_script_dir: Path,
        shared_scripts_dir: Path,
        customer: str,
        ckpt: Checkpoint,
        region: str,
        instance_count: int,
        wg_state_path: Path = None,
    ) -> None:
        super().__init__(args, cloud_script_dir, shared_scripts_dir, customer, ckpt)
        self.region = region
        self.instance_count = instance_count
        self.wg_state_path = wg_state_path

    def clear_remote_checkpoints(self) -> None:
        """Clear remote node checkpoints on all edge instances."""
        region = self.region
        customer = self.customer
        names = [f"{customer}-aws-edge-{region}-{i + 1}" for i in range(self.instance_count)]

        log.info("Clearing remote checkpoints on %d edge node(s)...", len(names))
        for name in names:
            try:
                iid = AwsNode.get_instance_id(name, region)
            except SystemExit:
                log.info("  %s: not found, skipping.", name)
                continue
            AwsNode.clear_node_checkpoints(iid, region, name)

    def _setup_wireguard(self) -> Optional["EdgeWireguard"]:
        """Phase 0: WireGuard credential setup. Returns None if ctrl is unreachable or install-only."""
        args = self.args

        if getattr(args, "install_only", False):
            log.info("Install-only mode — skipping WireGuard setup.")
            return None
        ckpt = self.ckpt
        customer = self.customer
        instance_count = self.instance_count
        wg_state_path = self.wg_state_path

        cp_cloud = getattr(args, "ctrl_cloud", None) or "aws"
        has_gateway = getattr(args, "has_gateway", None)
        if has_gateway is None:
            has_gateway = (cp_cloud == "aws")

        if ckpt.is_done("phase0_wireguard"):
            log.info("Already done (checkpoint found), loading.")
            wg = EdgeWireguard.load(wg_state_path, instance_count, has_gateway=has_gateway)
            wg.expand_if_needed(instance_count, "aws-edge",
                                cp_cloud=cp_cloud, cp_customer=customer, has_gateway=has_gateway)
            return wg

        try:
            if wg_state_path.exists():
                log.info("Loading existing wireguard.state: %s", wg_state_path)
                wg = EdgeWireguard.load(wg_state_path, instance_count, has_gateway=has_gateway)
            else:
                log.info("No wireguard.state found — auto-reserving WireGuard addresses...")
                wg = EdgeWireguard.create(
                    state_path=wg_state_path,
                    cp_cloud=cp_cloud,
                    cp_customer=customer,
                    instance_count=instance_count,
                    owner_prefix="aws-edge",
                    has_gateway=has_gateway,
                )
            wg.expand_if_needed(instance_count, "aws-edge",
                                cp_cloud=cp_cloud, cp_customer=customer, has_gateway=has_gateway)
            wg.validate_capacity(instance_count)
            ckpt.done("phase0_wireguard")
            return wg
        except SystemExit:
            log.warning("Control plane not reachable — WireGuard setup skipped.")
            log.warning("Edge nodes will be provisioned with packages only (phase 1).")
            log.warning("Re-run after ctrl is up to complete phase 2 (VPN + join).")
            return None

    def run(self) -> None:
        args = self.args
        ckpt = self.ckpt
        customer = self.customer
        region = self.region
        instance_count = self.instance_count

        # --- Phase 0: WireGuard setup (may fail if ctrl not up) ---
        log.info("")
        log.info("=== Phase 0: WireGuard setup ===")
        wg = self._setup_wireguard()

        # --- Phase 1: Resolve instances + package installation ---
        log.info("")
        log.info("=== Phase 1: Resolve instances ===")
        tarball_bytes = self.build_tarball()
        log.info("Bootstrap tarball built: %d bytes", len(tarball_bytes))

        instance_names = [f"{customer}-aws-edge-{region}-{i + 1}" for i in range(instance_count)]
        instance_ids: list[str] = []
        for name in instance_names:
            iid = AwsNode.get_instance_id(name, region)
            log.info("  %s -> %s", name, iid)
            instance_ids.append(iid)

        if wg is None:
            # Ctrl not reachable — run phase 1 (packages) only
            log.info("")
            log.info("=== Phase 1: Package installation only (ctrl not available) ===")
            from aws import AwsNode as _AwsNode
            for name, iid in zip(instance_names, instance_ids):
                ck_name = f"phase1_packages_{name}"
                if ckpt.is_done(ck_name):
                    log.info("--- %s — packages already done, skipping.", name)
                    continue
                log.info("[%s] Deploying bundle and installing packages...", name)
                # Create a minimal node just for package installation
                node = AwsEdgeNode(
                    instance_id=iid,
                    display_name=name,
                    region=region,
                    timeout=args.timeout,
                    tarball_bytes=tarball_bytes,
                    env_config="",  # no WG config
                )
                node.skip_packages = getattr(args, "skip_packages", False)
                node.verbose = getattr(args, "v", False)
                node.wait()
                node.print_access_command()
                node.deploy_bundle()
                node.run_install_packages()
                ckpt.done(ck_name)
            log.info("")
            log.info("=== Phase 1 complete. %d edge node(s) have packages installed. ===", instance_count)
            log.info("Re-run after ctrl is up to complete VPN setup and cluster join.")
            return

        # --- Phase 2: Full edge node deployment (VPN + join) ---
        log.info("")
        log.info("=== Phase 2: Edge node deployment ===")
        nodes: list[tuple[AwsEdgeNode, str]] = []
        for idx, (name, iid) in enumerate(zip(instance_names, instance_ids)):
            ck_name = f"phase2_edge_{name}"
            if ckpt.is_done(ck_name):
                log.info("--- %s — already done (checkpoint), skipping.", name)
                continue
            node = AwsEdgeNode(
                instance_id=iid,
                display_name=name,
                region=region,
                timeout=args.timeout,
                tarball_bytes=tarball_bytes,
                env_config=wg.build_node_config(wg.addresses[idx], idx),
            )
            node.skip_packages = getattr(args, "skip_packages", False)
            node.verbose = getattr(args, "v", False)
            nodes.append((node, ck_name))

        run_parallel(nodes, ckpt)

        log.info("")
        log.info("=== All %d AWS edge instance(s) successfully joined the cluster. ===", instance_count)


# ---------------------------------------------------------------------------
# Entrypoint (delegates to unified orchestration/install.py)
# ---------------------------------------------------------------------------


def _entrypoint() -> None:
    from kubeadm_cli import main

    sys.argv += ["--edge-cloud", "aws"]
    main()


if __name__ == "__main__":
    _entrypoint()
