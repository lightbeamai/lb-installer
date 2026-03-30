#!/usr/bin/env python3
"""AWS kubeadm installer — concrete CloudInstaller for ctrl-plane on AWS."""

from __future__ import annotations

import argparse
import logging
import subprocess
import sys
from pathlib import Path
from typing import Dict, Union

_repo_root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
sys.path.insert(0, str(_repo_root / "orchestration" / "lib"))
sys.path.insert(0, str(_repo_root / "orchestration"))

from bootstrapper import CtrlInstaller, run_parallel
from common import Checkpoint
from wireguard import KubeadmWireguard
from aws import AwsControllerNode, AwsGatewayNode, AwsNode, AwsWorkerNode

log = logging.getLogger(__name__)

SKIP_PACKAGE_INSTALL: bool = False
SKIP_CONFIG_NODE: bool = False


class AwsKubeadmInstaller(CtrlInstaller):
    """Installs a kubeadm control-plane cluster on AWS via SSM.

    All data is passed via __init__ — no tfvars reads or terraform output queries.
    """

    def __init__(
        self,
        args: argparse.Namespace,
        cloud_script_dir: Path,
        shared_scripts_dir: Path,
        customer: str,
        ckpt: Checkpoint,
        region: str,
        worker_count: int = 0,
        cp_ip: str = "",
        cp_public_ip: str = "",
    ) -> None:
        super().__init__(args, cloud_script_dir, shared_scripts_dir, customer, ckpt)
        self.region = region
        self.worker_count = worker_count
        self.cp_ip = cp_ip
        self.cp_public_ip = cp_public_ip

    def clear_remote_checkpoints(self) -> None:
        customer = self.customer
        region = self.region

        names: list[str] = []
        if not getattr(self.args, "skip_gateway", False):
            names.append(f"{customer}-lightbeam-gateway")
        if not getattr(self.args, "skip_cp", False):
            names.append(f"{customer}-lightbeam-control-plane")
        if not getattr(self.args, "skip_workers", False):
            names += [f"{customer}-lightbeam-worker-{i + 1}" for i in range(self.worker_count)]

        if not names:
            log.info("All node groups skipped; nothing to reset.")
            return

        log.info("Clearing remote checkpoints on %d node(s)...", len(names))
        for name in names:
            try:
                iid = AwsNode.get_instance_id(name, region)
            except SystemExit:
                log.info("  %s: not found, skipping.", name)
                continue
            except Exception as exc:
                log.warning("  %s: error (skipping): %s", name, exc)
                continue
            AwsNode.clear_node_checkpoints(iid, region, name)

    def _cloud_files(self) -> Dict[str, "Union[Path, bytes]"]:
        ctrl = self._scripts_dir / "ctrl"
        return {
            "cloud/aws_install.sh": ctrl / "cloud" / "aws_install.sh",
        }

    def run(self) -> None:
        from installer import aws

        args = self.args
        ckpt = self.ckpt
        customer = self.customer
        region = self.region
        worker_count = self.worker_count
        cp_ip = self.cp_ip
        cp_public_ip = self.cp_public_ip

        log.info("Worker count: %d", worker_count)

        cp_name = f"{customer}-lightbeam-control-plane"
        gateway_name = f"{customer}-lightbeam-gateway"

        wg = KubeadmWireguard.stage(
            explicit_dir=None,
            tfvars_dir=None,
            orchestration_script_dir=self.cloud_script_dir,
            fallback_module_dirs=[self.cloud_script_dir],
        )
        log.info("  wireguardconfigs=%s", wg.wg_configs_dir)

        server_conf_path = wg.wg_configs_dir / "server.conf"
        wg_server_conf = server_conf_path.read_text() if server_conf_path.exists() else ""

        tarball_bytes = self.build_tarball(wg_configs_dir=wg.wg_configs_dir)
        log.info("Unified bootstrap tarball built: %d bytes", len(tarball_bytes))

        cp_instance_id = AwsNode.get_instance_id(cp_name, region)
        log.info("Control plane instance ID: %s", cp_instance_id)
        log.info("Control plane IPs: private=%s public=%s", cp_ip, cp_public_ip or "(none)")

        # --- Phase 0: Gateway ---
        log.info("")
        log.info("=== Phase 0: Gateway setup ===")
        if args.skip_gateway:
            log.info("Skipping (--skip-gateway).")
        elif ckpt.is_done("phase0_gateway"):
            log.info("Already done (checkpoint found), skipping.")
        else:
            gateway_id = AwsNode.get_instance_id(gateway_name, region)
            log.info("Gateway instance ID: %s", gateway_id)
            if not wg_server_conf:
                log.warning("WireGuard server.conf not found at %s", server_conf_path)
            gw_node = AwsGatewayNode(
                instance_id=gateway_id,
                display_name=gateway_name,
                region=region,
                timeout=args.timeout,
                tarball_bytes=tarball_bytes,
                cp_private_ip=cp_ip,
            )
            gw_node.skip_packages = getattr(args, "skip_packages", False)
            gw_node.verbose = getattr(args, "v", False)
            gw_node.run()
            ckpt.done("phase0_gateway")

        gateway_ip = aws.get_gateway_public_ip(customer, region)

        cp_node = AwsControllerNode(
            instance_id=cp_instance_id,
            display_name=cp_name,
            region=region,
            timeout=args.timeout,
            customer=customer,
            tarball_bytes=tarball_bytes,
            gateway_ip=gateway_ip,
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

        cp_node._fetch_join_command()
        join_command = cp_node.join_command

        # --- Phase 2: Workers ---
        log.info("")
        log.info("=== Phase 2: Worker node bootstrap ===")
        if args.skip_workers or worker_count == 0:
            log.info("Skipping (--skip-workers or worker_count=0).")
        else:
            worker_names = [f"{customer}-lightbeam-worker-{i + 1}" for i in range(worker_count)]
            worker_ids: list[str] = []
            for name in worker_names:
                iid = AwsNode.get_instance_id(name, region)
                log.info("  %s -> %s", name, iid)
                worker_ids.append(iid)

            workers_to_run: list[tuple[AwsWorkerNode, str]] = []
            for name, iid in zip(worker_names, worker_ids):
                ck_name = f"phase2_worker_{name}"
                if ckpt.is_done(ck_name):
                    log.info("--- Worker: %s - already done (checkpoint), skipping.", name)
                    continue
                worker = AwsWorkerNode(
                    instance_id=iid,
                    display_name=f"{name} ({iid})",
                    region=region,
                    timeout=args.timeout,
                    customer=customer,
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
            aws.wait_for_workers_ready(cp_node, worker_count, timeout=args.timeout)
            ckpt.done("phase3_cluster_ready")

        log.info("")
        log.info("=== Cluster installation complete ===")
        log.info("  Control plane: %s (%s)", cp_name, cp_instance_id)
        log.info("  Workers:       %d", worker_count)
        log.info("")
        log.info("To access the cluster via SSM:")
        log.info("  aws ssm start-session --region %s --target %s", region, cp_instance_id)
        log.info("  sudo kubectl get nodes -o wide")


def _entrypoint() -> None:
    from kubeadm_cli import main
    sys.argv += ["--ctrl-cloud", "aws"]
    main()


if __name__ == "__main__":
    _entrypoint()
