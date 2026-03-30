#!/usr/bin/env python3
"""GCP kubeadm installer — concrete CloudInstaller for ctrl-plane on GCP."""

from __future__ import annotations

import argparse
import logging
import subprocess
import sys
from pathlib import Path
from typing import Dict, Union

# Resolve import paths relative to the git repository root
_repo_root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
sys.path.insert(0, str(_repo_root / "orchestration" / "lib"))
sys.path.insert(0, str(_repo_root / "orchestration"))

from bootstrapper import CtrlInstaller
from bootstrapper import run_parallel
from common import Checkpoint
from wireguard import KubeadmWireguard
from gcp import GcpControllerNode, GcpWorkerNode

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Phase skip flags — set to True to bypass the corresponding bootstrap phase.
#
#   SKIP_PACKAGE_INSTALL  Package installation: packages.sh + master/worker_install.sh
#   SKIP_CONFIG_NODE  Cluster configuration: wireguard, kubeadm, calico, join, etc.
#
# Typical use-cases:
#   SKIP_PACKAGE_INSTALL = True   Packages already installed; re-run config only.
#   SKIP_CONFIG_NODE = True   Install packages now; configure the cluster later.
# ---------------------------------------------------------------------------
SKIP_PACKAGE_INSTALL: bool = False
SKIP_CONFIG_NODE: bool = False

# ---------------------------------------------------------------------------
# Installer
# ---------------------------------------------------------------------------


class GcpKubeadmInstaller(CtrlInstaller):
    """Installs a kubeadm control-plane cluster on GCP via IAP SSH."""

    def __init__(
        self,
        args: argparse.Namespace,
        cloud_script_dir: Path,
        shared_scripts_dir: Path,
        customer: str,
        ckpt: Checkpoint,
        project: str,
        zone: str,
        worker_count: int,
        cp_ip: str = "",
        cp_public_ip: str = "",
    ) -> None:
        super().__init__(args, cloud_script_dir, shared_scripts_dir, customer, ckpt)
        self.project = project
        self.zone = zone
        self.worker_count = worker_count
        self.cp_ip = cp_ip
        self.cp_public_ip = cp_public_ip

    def clear_remote_checkpoints(self) -> None:
        """Clear remote node checkpoint markers on nodes managed by this installer.

        Respects ``--skip-cp`` and ``--skip-workers`` so that skipped node
        groups are not touched during a reset.
        """
        from gcp import GcpNode

        customer = self.customer
        names: list[str] = []
        if not getattr(self.args, "skip_cp", False):
            names.append(f"{customer}-lightbeam-control-plane")
        if not getattr(self.args, "skip_workers", False):
            names += [f"{customer}-lightbeam-worker-{i + 1}" for i in range(self.worker_count)]

        if not names:
            log.info("All node groups skipped; nothing to reset.")
            return

        log.info("Clearing remote checkpoints on %d node(s)...", len(names))
        for name in names:
            GcpNode.clear_node_checkpoints(self.project, self.zone, name)

    def _cloud_files(self) -> Dict[str, "Union[Path, bytes]"]:
        ctrl = self._scripts_dir / "ctrl"
        return {
            "cloud/gcp_install.sh": ctrl / "cloud" / "gcp_install.sh",
        }

    def run(self) -> None:
        from installer import gcp

        args = self.args
        ckpt = self.ckpt
        customer = self.customer
        project = self.project
        zone = self.zone
        worker_count = self.worker_count
        cp_ip = self.cp_ip
        cp_public_ip = self.cp_public_ip

        cp_name = f"{customer}-lightbeam-control-plane"

        wg = KubeadmWireguard.stage(
            explicit_dir=None,
            tfvars_dir=None,
            orchestration_script_dir=self.cloud_script_dir,
            fallback_module_dirs=[self.cloud_script_dir],
        )
        log.info("  wireguardconfigs=%s", wg.wg_configs_dir)
        log.info("  control-plane: %s", cp_name)

        tarball_bytes = self.build_tarball(wg_configs_dir=wg.wg_configs_dir)
        log.info("Bootstrap tarball built: %d bytes", len(tarball_bytes))

        log.info("Control plane IPs: private=%s public=%s", cp_ip, cp_public_ip or "(none)")

        cp_node = GcpControllerNode(
            project=project,
            zone=zone,
            timeout=args.timeout,
            customer=customer,
            cp_name=cp_name,
            tarball_bytes=tarball_bytes,
            private_ip=cp_ip,
            public_ip=cp_public_ip,
            skip_package_install=SKIP_PACKAGE_INSTALL,
            skip_config_node=SKIP_CONFIG_NODE,
            verbose=args.v,
        )
        cp_node.skip_packages = getattr(args, "skip_packages", False)
        cp_node.verbose = getattr(args, "v", False)

        # --- Phase 1: Control plane ---
        log.info("")
        log.info("=== Phase 1: Control plane bootstrap ===")
        if args.skip_cp:
            log.info("Skipping (--skip-cp).")
        elif ckpt.is_done("phase1_cp"):
            log.info("Already done (checkpoint found), skipping.")
        else:
            cp_node.run()
            log.info("Control plane kubeadm init completed.")
            ckpt.done("phase1_cp")

        # Fetch join command — either from monitor or by reading from existing cluster
        # Always generate a fresh join command (tokens expire after 24h)
        cp_node._fetch_join_command()
        join_command = cp_node.join_command

        # --- Phase 2: Workers ---
        log.info("")
        log.info("=== Phase 2: Worker node bootstrap ===")
        if args.skip_workers or worker_count == 0:
            log.info("Skipping (--skip-workers or worker_count=0).")
        else:
            worker_names = [f"{customer}-lightbeam-worker-{i + 1}" for i in range(worker_count)]

            workers_to_run: list[tuple[GcpWorkerNode, str]] = []
            for worker_name in worker_names:
                ck_name = f"phase2_worker_{worker_name}"
                if ckpt.is_done(ck_name):
                    log.info("--- Worker: %s - already done (checkpoint), skipping.", worker_name)
                    continue
                worker = GcpWorkerNode(
                    project=project,
                    zone=zone,
                    timeout=args.timeout,
                    customer=customer,
                    worker_name=worker_name,
                    tarball_bytes=tarball_bytes,
                    cp_ip=cp_ip,
                    join_command=join_command,
                    skip_package_install=SKIP_PACKAGE_INSTALL,
                    skip_config_node=SKIP_CONFIG_NODE,
                )
                worker.skip_packages = getattr(args, "skip_packages", False)
                worker.verbose = getattr(args, "v", False)
                workers_to_run.append((worker, ck_name))

            run_parallel(workers_to_run, ckpt)

        # --- Phase 3: Cluster readiness ---
        log.info("")
        log.info("=== Phase 3: Cluster readiness ===")
        if ckpt.is_done("phase3_cluster_ready"):
            log.info("Already done (checkpoint found), skipping.")
        else:
            gcp.wait_for_workers_ready(cp_node, worker_count, timeout=args.timeout)
            ckpt.done("phase3_cluster_ready")

        log.info("")
        log.info("=== Cluster installation complete ===")
        log.info("  Control plane: %s", cp_name)
        log.info("  Workers:       %d", worker_count)
        log.info("")
        log.info("To access the cluster:")
        log.info(
            "  gcloud compute ssh %s --project %s --zone %s --tunnel-through-iap",
            cp_name, project, zone,
        )
        log.info("  sudo kubectl get nodes -o wide")


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------


def _entrypoint() -> None:
    from kubeadm_cli import main

    sys.argv += ["--ctrl-cloud", "gcp"]
    main()


if __name__ == "__main__":
    _entrypoint()
