#!/usr/bin/env python3
"""GCP Edge Node installer — concrete CloudInstaller for edge nodes on GCP."""

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
from gcp import GcpEdgeNode

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Concrete installer class
# ---------------------------------------------------------------------------


class GcpEdgeInstaller(EdgeInstaller):
    """Installs edge nodes on GCP via IAP SSH."""

    def __init__(
        self,
        args: argparse.Namespace,
        cloud_script_dir: Path,
        shared_scripts_dir: Path,
        customer: str,
        ckpt: Checkpoint,
        project: str,
        zone: str,
        instance_count: int,
        wg_state_path: Path = None,
    ) -> None:
        super().__init__(args, cloud_script_dir, shared_scripts_dir, customer, ckpt)
        self.project = project
        self.zone = zone
        self.instance_count = instance_count
        self.wg_state_path = wg_state_path

    def clear_remote_checkpoints(self) -> None:
        """Clear remote node checkpoints on all edge instances."""
        from gcp import GcpNode
        instances = [f"{self.customer}-gcp-edge-{self.zone}-{i + 1}" for i in range(self.instance_count)]
        log.info("Clearing remote checkpoints on %d edge node(s)...", len(instances))
        for name in instances:
            GcpNode.clear_node_checkpoints(self.project, self.zone, name)

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

        cp_cloud = getattr(args, "ctrl_cloud", None) or "gcp"
        has_gateway = getattr(args, "has_gateway", None)
        if has_gateway is None:
            has_gateway = (cp_cloud == "aws")

        if ckpt.is_done("phase0_wireguard"):
            log.info("Already done (checkpoint found), loading.")
            wg = EdgeWireguard.load(wg_state_path, instance_count, has_gateway=has_gateway)
            wg.expand_if_needed(instance_count, "gcp-edge",
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
                    owner_prefix="gcp-edge",
                    has_gateway=has_gateway,
                )
            wg.expand_if_needed(instance_count, "gcp-edge",
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
        project = self.project
        zone = self.zone
        instance_count = self.instance_count

        # --- Phase 0: WireGuard setup (may fail if ctrl not up) ---
        log.info("")
        log.info("=== Phase 0: WireGuard setup ===")
        wg = self._setup_wireguard()

        # --- Phase 1: Resolve instances ---
        log.info("")
        log.info("=== Phase 1: Resolve instances ===")
        tarball_bytes = self.build_tarball()
        log.info("Bootstrap tarball built: %d bytes", len(tarball_bytes))

        instances = [f"{customer}-gcp-edge-{zone}-{i + 1}" for i in range(instance_count)]

        if wg is None:
            # Ctrl not reachable — run phase 1 (packages) only
            log.info("")
            log.info("=== Phase 1: Package installation only (ctrl not available) ===")
            for instance in instances:
                ck_name = f"phase1_packages_{instance}"
                if ckpt.is_done(ck_name):
                    log.info("--- %s — packages already done, skipping.", instance)
                    continue
                log.info("[%s] Deploying bundle and installing packages...", instance)
                node = GcpEdgeNode(
                    project=project,
                    zone=zone,
                    timeout=args.timeout,
                    instance=instance,
                    tarball_bytes=tarball_bytes,
                    env_config="",
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
        nodes: list[tuple[GcpEdgeNode, str]] = []
        for idx, instance in enumerate(instances):
            ck_name = f"phase2_edge_{instance}"
            if ckpt.is_done(ck_name):
                log.info("--- %s — already done (checkpoint), skipping.", instance)
                continue
            node = GcpEdgeNode(
                project=project,
                zone=zone,
                timeout=args.timeout,
                instance=instance,
                tarball_bytes=tarball_bytes,
                env_config=wg.build_node_config(wg.addresses[idx], idx),
            )
            node.skip_packages = getattr(args, "skip_packages", False)
            node.verbose = getattr(args, "v", False)
            nodes.append((node, ck_name))

        run_parallel(nodes, ckpt)

        log.info("")
        log.info("=== All %d GCP edge instance(s) successfully joined the cluster. ===", instance_count)


# ---------------------------------------------------------------------------
# Entrypoint (delegates to unified orchestration/install.py)
# ---------------------------------------------------------------------------


def _entrypoint() -> None:
    from kubeadm_cli import main

    sys.argv += ["--edge-cloud", "gcp"]
    main()


if __name__ == "__main__":
    _entrypoint()
