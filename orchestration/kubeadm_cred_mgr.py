#!/usr/bin/env python3
"""Manage edge node credentials and WireGuard address reservations.

Actions:
  publish  - Reserve addresses, fetch credentials, write edge-config.env files
  reserve  - Reserve N WireGuard addresses (without generating config files)
  release  - Release specific WireGuard addresses
  list     - Show current WireGuard address reservations

Usage:
    # Publish credentials for one edge node
    python edge_credentials.py --customer hstest --ctrl-cloud aws --action publish

    # Publish for 3 edge nodes
    python edge_credentials.py --customer hstest --ctrl-cloud aws --action publish --count 3

    # Reserve 5 addresses without generating configs
    python edge_credentials.py --customer hstest --ctrl-cloud aws --action reserve --count 5

    # Release specific addresses
    python edge_credentials.py --customer hstest --ctrl-cloud aws --action release --addresses 10.8.0.5,10.8.0.6

    # List current reservations
    python edge_credentials.py --customer hstest --ctrl-cloud aws --action list
"""

import argparse
import logging
import os
import subprocess
import sys
from pathlib import Path

_repo_root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
sys.path.insert(0, str(_repo_root / "orchestration" / "lib"))
sys.path.insert(0, str(_repo_root / "orchestration"))

from common import die

logging.basicConfig(
    format="[%(asctime)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    level=logging.INFO,
)
log = logging.getLogger(__name__)

for _name in ("botocore.credentials", "botocore.utils", "boto3.resources.action"):
    logging.getLogger(_name).setLevel(logging.WARNING)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Manage edge node credentials and WireGuard address reservations.",
        epilog=(
            "On the edge node:\n"
            "  1. Place bootstrap scripts at /var/lib/lightbeam/bootstrap/\n"
            "  2. Copy edge-config.env to /var/lib/lightbeam/bootstrap/\n"
            "  3. Run: sudo bash /var/lib/lightbeam/bootstrap/worker_edge.sh\n"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--customer", required=True, help="Customer name")
    parser.add_argument("--ctrl-cloud", required=True, choices=["aws", "gcp"],
                        help="Control-plane cloud")
    parser.add_argument("--action", required=True,
                        choices=["reserve", "release", "list"],
                        help="Action: reserve (reserve addresses + write config files), release, list")
    parser.add_argument("--edge-cloud", default=None, choices=["aws", "gcp"],
                        help="Edge cloud (for WG reservation owner; defaults to --ctrl-cloud)")
    parser.add_argument("--count", type=int, default=1,
                        help="Number of addresses to reserve/publish (default: 1)")
    parser.add_argument("--addresses",
                        help="Comma-separated WireGuard addresses to release (e.g. 10.8.0.5,10.8.0.6)")
    parser.add_argument("--output-dir", type=Path, default=None,
                        help="Directory to write credential files (default: LIGHTBEAM_DEPLOYMENT_ROOT/{customer}_{edge}-edge/)")
    parser.add_argument("--has-gateway", action="store_true", default=None,
                        help="Control-plane uses a gateway node (default: True for AWS)")
    return parser.parse_args()


def _resolve_output_dir(args) -> Path:
    """Resolve output directory: explicit --output-dir or LIGHTBEAM_DEPLOYMENT_ROOT/{customer}_{edge}-edge/."""
    if args.output_dir:
        return args.output_dir.resolve()
    deploy_root = os.getenv("LIGHTBEAM_DEPLOYMENT_ROOT", "").strip()
    if not deploy_root:
        die("Set --output-dir or LIGHTBEAM_DEPLOYMENT_ROOT.")
    edge_cloud = args.edge_cloud or args.ctrl_cloud
    dir_name = f"{args.customer}_{edge_cloud}-edge"
    return (Path(deploy_root) / dir_name).resolve()


def _get_context(args):
    """Build control plane context and reservation manager."""
    from credentials import load_control_plane_context
    from wireguard import WireguardReservations

    has_gateway = args.has_gateway
    if has_gateway is None:
        has_gateway = (args.ctrl_cloud == "aws")

    ctx = load_control_plane_context(args.ctrl_cloud, args.customer, has_gateway=has_gateway)
    reservations = WireguardReservations(ctx)
    return ctx, reservations, has_gateway


def _action_list(args) -> None:
    """Show current WireGuard address reservations."""
    _, reservations, _ = _get_context(args)
    reservations.load()
    raw = reservations.raw

    if not raw.strip():
        log.info("No WireGuard address reservations found.")
        return

    log.info("WireGuard address reservations for %s (%s):", args.customer, args.ctrl_cloud)
    print()
    print(f"  {'Address':<18s} {'Owner':<40s} {'Reserved At'}")
    print(f"  {'-'*17:<18s} {'-'*39:<40s} {'-'*20}")
    for line in raw.strip().splitlines():
        parts = line.split("|")
        if len(parts) >= 3:
            print(f"  {parts[0]:<18s} {parts[1]:<40s} {parts[2]}")
        elif len(parts) == 2:
            print(f"  {parts[0]:<18s} {parts[1]:<40s}")
    print()


def _action_reserve(args) -> None:
    """Reserve WireGuard addresses, fetch credentials, and write edge-config.env files."""
    from wireguard import (
        _fetch_credentials_and_configs,
        _build_node_env_config,
        WireguardReservations,
    )
    from credentials import load_control_plane_context

    customer = args.customer
    ctrl_cloud = args.ctrl_cloud
    edge_cloud = args.edge_cloud or ctrl_cloud
    count = args.count
    output_dir = _resolve_output_dir(args)

    has_gateway = args.has_gateway
    if has_gateway is None:
        has_gateway = (ctrl_cloud == "aws")

    output_dir.mkdir(parents=True, exist_ok=True)

    log.info("=== Edge Credential Reserve ===")
    log.info("  Customer:     %s", customer)
    log.info("  Ctrl cloud:   %s", ctrl_cloud)
    log.info("  Edge cloud:   %s", edge_cloud)
    log.info("  Count:        %d", count)
    log.info("  Output dir:   %s", output_dir)

    # Fetch credentials from control plane
    log.info("")
    log.info("Connecting to control plane...")
    creds, wg_configs = _fetch_credentials_and_configs(
        cp_cloud=ctrl_cloud,
        cp_customer=customer,
        has_gateway=has_gateway,
    )

    # Reserve addresses
    log.info("")
    log.info("Reserving %d WireGuard address(es)...", count)
    ctx = load_control_plane_context(ctrl_cloud, customer, has_gateway=has_gateway)
    reservations = WireguardReservations(ctx)
    owner_prefix = f"{edge_cloud}-edge"
    addresses = reservations.auto_reserve(count, owner_prefix)
    log.info("  Reserved: %s", ", ".join(addresses))

    # Generate and write credential files
    log.info("")
    files_written = []
    for i, address in enumerate(addresses):
        env_content = _build_node_env_config(address, i, creds, wg_configs)

        ip = address.split("/")[0]
        filename = f"edge-config-{ip}.env"
        filepath = output_dir / filename

        if filepath.exists():
            overwrite = input(f"  {filepath} already exists. Overwrite? [y/N]: ").strip().lower()
            if overwrite not in ("y", "yes"):
                log.info("  Skipped: %s", filepath)
                continue

        filepath.write_text(env_content)
        os.chmod(str(filepath), 0o600)
        files_written.append(filepath)
        log.info("  Written: %s", filepath)

    log.info("")
    log.info("=== Done ===")
    if files_written:
        log.info("")
        log.info("Files generated:")
        for f in files_written:
            log.info("  %s", f)
        log.info("")
        log.info("To join an edge node:")
        log.info("  1. Copy bootstrap scripts to /var/lib/lightbeam/bootstrap/ on the edge node")
        log.info("  2. Copy the env file to /var/lib/lightbeam/bootstrap/edge-config.env")
        log.info("  3. Run: sudo bash /var/lib/lightbeam/bootstrap/worker_edge.sh")


def _action_release(args) -> None:
    """Release specific WireGuard addresses."""
    if not args.addresses:
        die("--addresses is required for release (e.g. --addresses 10.8.0.5,10.8.0.6)")

    addresses = [a.strip() for a in args.addresses.split(",") if a.strip()]
    if not addresses:
        die("No valid addresses provided.")

    _, reservations, _ = _get_context(args)
    reservations.load()

    log.info("Releasing %d WireGuard address(es)...", len(addresses))
    for addr in addresses:
        # Normalize: add /24 if missing
        if "/" not in addr:
            addr = f"{addr}/24"
        reservations.release(addr)

    log.info("Done.")


def main() -> None:
    args = parse_args()

    if args.action == "list":
        _action_list(args)
    elif args.action == "reserve":
        _action_reserve(args)
    elif args.action == "release":
        _action_release(args)


if __name__ == "__main__":
    main()
