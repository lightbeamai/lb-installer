#!/usr/bin/env python3
"""Kubeadm cluster management CLI."""

import argparse
import logging
import os
import subprocess
import sys
from pathlib import Path

# Resolve import paths
_repo_root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
sys.path.insert(0, str(_repo_root / "orchestration" / "lib"))
sys.path.insert(0, str(_repo_root / "orchestration"))

from common import Checkpoint, die
from helpers import setup_logging, prompt
from tf_mgr import resolve_tf_script
from tfvars import resolve_tfvars_from_deployment_root
from deployment_mgr import (
    KubeadmDeployment, edge_deployment_type,
    parse_edge_cloud_spec,
    print_full_summary, show_deployments, detect_ctrl_cloud,
)
from kubeadm.kubernetes_cluster_mgr import (
    clear_remote_checkpoints,
    run_install, add_ctrl_worker, remove_ctrl_worker,
    add_edge_worker, remove_edge_worker,
)

setup_logging()
log = logging.getLogger(__name__)


def _build_deployments(customer, ctrl_cloud, do_ctrl, edge_specs, do_edge):
    """Build list of KubeadmDeployment objects from CLI flags."""
    deployments = []
    if do_ctrl:
        deployments.append(KubeadmDeployment(customer, ctrl_cloud, "ctrl"))
    if do_edge:
        for ec, er in edge_specs:
            deployments.append(KubeadmDeployment(customer, ec, "edge", er))
    return deployments


def parse_args() -> argparse.Namespace:
    # Print env info upfront
    tf_iac_root = os.getenv("LIGHTBEAM_TF_IAC_ROOT", "")
    deploy_root = os.getenv("LIGHTBEAM_DEPLOYMENT_ROOT", "")

    parser = argparse.ArgumentParser(
        description="Bootstrap a kubeadm cluster on AWS/GCP.",
        epilog=(
            f"Environment:\n"
            f"  LIGHTBEAM_TF_IAC_ROOT      = {tf_iac_root or '(not set)'}\n"
            f"  LIGHTBEAM_DEPLOYMENT_ROOT   = {deploy_root or '(not set)'}\n"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--ctrl-cloud",
        choices=["aws", "gcp"],
        help="Control-plane cloud (auto-detected from customer if omitted).",
    )
    parser.add_argument(
        "--edge-cloud",
        nargs="+",
        help="Edge cloud(s) to deploy, space or comma-separated (auto-detected from customer if omitted).",
    )

    # Provider overrides
    parser.add_argument("--region", help="AWS region (overrides tfvars)")
    parser.add_argument("--project", help="GCP project ID (overrides tfvars)")
    parser.add_argument("--zone", help="GCP zone (overrides tfvars)")

    parser.add_argument("--customer", help="Customer name used in deployment state directory name")
    parser.add_argument("--has-gateway", action="store_true", default=None,
                        help="Control-plane uses a gateway node for WireGuard (edge mode; defaults to True for aws ctrl-cloud)")

    # Image resolution
    parser.add_argument("--no-published-image", action="store_true",
                        help="Ignore published images and use the default OS image from terraform")

    # Install phases
    parser.add_argument("--install-only", action="store_true", help="Run phase 1 (packages) only, skip phase 2 (VPN + join)")
    parser.add_argument("--skip-packages", action="store_true", help="Skip phase 1 package installation (use with pre-baked AMIs)")
    parser.add_argument(
        "--skip",
        nargs="+",
        metavar="PHASE",
        help="Skip phases: gateway, cp, workers (e.g. --skip gateway workers)",
    )
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument(
        "--v",
        action="store_true",
        help="Verbose node log streaming (default: off)",
    )

    # Worker/edge scaling
    parser.add_argument(
        "--add",
        nargs="+",
        metavar="TYPE",
        help="Add nodes: worker (ctrl workers) or edge (edge workers). E.g. --add worker, --add edge",
    )
    parser.add_argument(
        "--remove",
        nargs="+",
        metavar="TYPE",
        help="Remove nodes: worker (ctrl workers) or edge (edge workers). E.g. --remove worker, --remove edge",
    )

    # Actions
    parser.add_argument(
        "--action",
        choices=["init", "apply", "install", "destroy", "cleanup-state", "output", "show", "all"],
        default="all",
        help=(
            "Action to perform (default: all):\n"
            "  all            - init + apply + install in sequence\n"
            "  init           - terraform init only\n"
            "  apply          - terraform apply only\n"
            "  install        - kubeadm orchestration only; assumes infra exists\n"
            "  destroy        - terraform destroy\n"
            "  output         - terraform output\n"
            "  show           - show configured deployments\n"
            "  cleanup-state  - cleanup terraform runtime artifacts"
        ),
    )
    parser.add_argument(
        "--scope",
        choices=["ctrl", "edge", "all"],
        default=None,
        help=(
            "Limit action to ctrl or edge only (default: inferred from flags).\n"
            "Use when both --ctrl-cloud and --edge-cloud are specified but you\n"
            "want to act on only one. E.g. --scope edge --action destroy"
        ),
    )
    parser.add_argument(
        "--reset",
        metavar="STAGE",
        nargs="?",
        const="all",
        help=(
            "Clear checkpoints before running. Omit STAGE to reset all, or pass a stage name "
            "(e.g. phase0_gateway, phase1_cp, phase2_worker_<name>, phase3_cluster_ready)."
        ),
    )
    args = parser.parse_args()

    # Normalize comma-separated values for multi-value args
    def _split_csv(vals):
        """Split ['a,b', 'c'] into ['a', 'b', 'c']."""
        if not vals:
            return vals
        result = []
        for v in vals:
            result.extend(s.strip() for s in v.split(",") if s.strip())
        return result

    args.skip = _split_csv(args.skip)
    args.add = _split_csv(args.add)
    args.remove = _split_csv(args.remove)
    args.edge_cloud = _split_csv(args.edge_cloud)

    # Normalize --skip into individual flags for backward compat with internal code
    skip_phases = set(args.skip or [])
    args.skip_gateway = "gateway" in skip_phases
    args.skip_cp = "cp" in skip_phases
    args.skip_workers = "workers" in skip_phases

    # Default internal attrs
    args.shared_scripts = None
    args.wireguard_state = None
    args.terraform_script = None

    return args




def main() -> None:
    args = parse_args()
    customer = (args.customer or os.getenv("LIGHTBEAM_CUSTOMER_NAME", "")).strip()

    ctrl_cloud = (args.ctrl_cloud or "").strip().lower()

    # Normalize edge clouds: support "aws:us-east-1", "aws,gcp", "aws:us-east-1,gcp:us-east1"
    # edge_specs is a list of (cloud, region) tuples
    raw_edges = args.edge_cloud or []
    edge_specs: list[tuple[str, str]] = []
    for item in raw_edges:
        for spec in item.split(","):
            spec = spec.strip()
            if spec:
                cloud, region = parse_edge_cloud_spec(spec)
                edge_specs.append((cloud, region))

    action = args.action

    # Handle --add / --remove
    if args.add or args.remove:
        if not customer:
            die("--customer is required for --add/--remove.")
        add_types = set(args.add or [])
        remove_types = set(args.remove or [])

        if "worker" in add_types:
            if not ctrl_cloud:
                ctrl_cloud = detect_ctrl_cloud(customer)
            add_ctrl_worker(args, ctrl_cloud, customer)
            return
        if "worker" in remove_types:
            if not ctrl_cloud:
                ctrl_cloud = detect_ctrl_cloud(customer)
            remove_ctrl_worker(args, ctrl_cloud, customer)
            return
        if "edge" in add_types:
            if not edge_specs:
                die("--edge-cloud is required for --add edge (e.g. --edge-cloud aws:us-east-1).")
            if len(edge_specs) != 1:
                die("Specify exactly one --edge-cloud for --add edge.")
            ec, er = edge_specs[0]
            add_edge_worker(args, ec, customer, region=er)
            return
        if "edge" in remove_types:
            if not edge_specs:
                die("--edge-cloud is required for --remove edge (e.g. --edge-cloud aws:us-east-1).")
            if len(edge_specs) != 1:
                die("Specify exactly one --edge-cloud for --remove edge.")
            ec, er = edge_specs[0]
            remove_edge_worker(args, ec, customer, region=er)
            return

        die("Unknown --add/--remove type. Use: worker, edge.")

    # Handle show action — shows deployment listing + terraform output
    if action == "show":
        show_deployments(customer)
        print()
        if ctrl_cloud or edge_specs:
            if not customer:
                die("--customer is required for --action show with specific clouds.")
            if ctrl_cloud:
                KubeadmDeployment(customer, ctrl_cloud, "ctrl").show_output()
            for ec, er in edge_specs:
                KubeadmDeployment(customer, ec, "edge", er).show_output()
        elif customer:
            for d in KubeadmDeployment.discover_all(customer):
                d.show_output()
        else:
            show_deployments()
        return

    # Auto-detect if neither specified
    if not ctrl_cloud and not edge_specs:
        if not customer:
            die("Pass --ctrl-cloud and/or --edge-cloud, or --customer to auto-detect.")
        ctrl_cloud = detect_ctrl_cloud(customer)
        edge_specs = [(d.cloud, d.region) for d in KubeadmDeployment.discover_edge(customer)]
        edge_labels = [f"{c}:{r}" if r else c for c, r in edge_specs]
        log.info("Auto-detected: ctrl=%s edges=%s", ctrl_cloud, edge_labels or "(none)")

    # Infer scope: what to act on
    scope = args.scope
    if scope is None:
        if ctrl_cloud and edge_specs:
            scope = "all"
        elif ctrl_cloud:
            scope = "ctrl"
        else:
            scope = "edge"

    do_ctrl = scope in ("ctrl", "all") and bool(ctrl_cloud)
    do_edge = scope in ("edge", "all") and bool(edge_specs)

    if not do_ctrl and not do_edge:
        die("Nothing to do. Pass --ctrl-cloud and/or --edge-cloud, and check --scope.")

    def _edge_label(cloud: str, region: str) -> str:
        return f"{cloud}-edge-{region}" if region else f"{cloud}-edge"

    action = args.action

    if action == "destroy":
        _deployments = _build_deployments(customer, ctrl_cloud, do_ctrl, edge_specs, do_edge)
        print_full_summary("Will destroy the following deployments", _deployments)
        confirm = prompt("\nType 'destroy' to confirm: ").strip()
        if confirm != "destroy":
            log.info("Destroy cancelled.")
            return

        if do_edge:
            for ec, er in edge_specs:
                log.info("=== Destroying %s ===", _edge_label(ec, er))
                run_install(args, ec, "edge", region=er)
        if do_ctrl:
            log.info("=== Destroying %s ctrl ===", ctrl_cloud)
            run_install(args, ctrl_cloud, "ctrl")
        return

    # Handle --reset early
    if args.reset:
        if do_ctrl:
            ctrl_tfvars = resolve_tfvars_from_deployment_root(customer, f"{ctrl_cloud}-ctrl")
            ctrl_ckpt = Checkpoint(ctrl_tfvars.parent / ".orchestration-state")
            ctrl_ckpt.clear(None if args.reset == "all" else args.reset)
            log.info("Cleared local checkpoints for %s-ctrl: %s", ctrl_cloud, args.reset)
            if args.reset == "all":
                clear_remote_checkpoints(args, ctrl_cloud, "ctrl", customer)
        if do_edge:
            for ec, er in edge_specs:
                dt = edge_deployment_type(ec, er)
                edge_tfvars = resolve_tfvars_from_deployment_root(customer, dt)
                edge_ckpt = Checkpoint(edge_tfvars.parent / ".orchestration-state")
                edge_ckpt.clear(None if args.reset == "all" else args.reset)
                log.info("Cleared local checkpoints for %s: %s", dt, args.reset)
                if args.reset == "all":
                    clear_remote_checkpoints(args, ec, "edge", customer, region=er)
        if args.reset == "all":
            return

    # For terraform-only actions, show summary and run
    if action in ("init", "apply", "output", "cleanup-state"):
        _deployments = _build_deployments(customer, ctrl_cloud, do_ctrl, edge_specs, do_edge)
        print_full_summary(f"Running terraform {action}", _deployments)

        if action == "apply":
            print("\n  [y] Proceed with apply")
            print("  [m] Modify configuration (run terraform configure)")
            print("  [n] Cancel")
            confirm = prompt("\nChoice [y/m/N]: ").strip().lower()
            if confirm == "m":
                from tf_mgr import run_terraform_sh
                if do_ctrl:
                    args.deployment_type = f"{ctrl_cloud}-ctrl"
                    tf_script = resolve_tf_script(args, mode="ctrl")
                    if tf_script:
                        log.info("=== Modifying %s-ctrl configuration ===", ctrl_cloud)
                        run_terraform_sh(tf_script, "configure", customer_name=customer)
                if do_edge:
                    for ec, er in edge_specs:
                        args.deployment_type = edge_deployment_type(ec, er)
                        tf_script = resolve_tf_script(args, mode="edge")
                        if tf_script:
                            log.info("=== Modifying %s configuration ===", args.deployment_type)
                            run_terraform_sh(tf_script, "configure", customer_name=customer)
                log.info("Configuration updated. Re-run to apply.")
                return
            if confirm not in ("y", "yes"):
                log.info("Cancelled.")
                return

        if do_ctrl:
            run_install(args, ctrl_cloud, "ctrl")
        if do_edge:
            for ec, er in edge_specs:
                run_install(args, ec, "edge", region=er)

        if action == "apply":
            for d in _deployments:
                d.show_output()
        return

    # Print summary and confirm for install/all
    _deployments = _build_deployments(customer, ctrl_cloud, do_ctrl, edge_specs, do_edge)
    print_full_summary("Will install the following deployments", _deployments)

    print("\n  [y] Proceed with install")
    print("  [m] Modify configuration (run terraform configure)")
    print("  [n] Cancel")
    confirm = prompt("\nChoice [y/m/N]: ").strip().lower()
    if confirm == "m":
        from tf_mgr import run_terraform_sh
        if do_ctrl:
            args.deployment_type = f"{ctrl_cloud}-ctrl"
            tf_script = resolve_tf_script(args, mode="ctrl")
            if tf_script:
                log.info("=== Modifying %s-ctrl configuration ===", ctrl_cloud)
                run_terraform_sh(tf_script, "configure", customer_name=customer)
        if do_edge:
            for ec, er in edge_specs:
                dt = edge_deployment_type(ec, er)
                args.deployment_type = dt
                tf_script = resolve_tf_script(args, mode="edge")
                if tf_script:
                    log.info("=== Modifying %s configuration ===", dt)
                    run_terraform_sh(tf_script, "configure", customer_name=customer)
        log.info("Configuration updated. Re-run to install.")
        return
    if confirm not in ("y", "yes"):
        log.info("Install cancelled.")
        return

    # Install: ctrl first, then edges sequentially
    if do_ctrl:
        log.info("=== Installing %s ctrl ===", ctrl_cloud)
        run_install(args, ctrl_cloud, "ctrl")

    if do_edge:
        for ec, er in edge_specs:
            log.info("=== Installing %s ===", _edge_label(ec, er))
            run_install(args, ec, "edge", region=er)


if __name__ == "__main__":
    main()
