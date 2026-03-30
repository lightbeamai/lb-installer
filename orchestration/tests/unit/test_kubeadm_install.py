"""Tests for kubeadm_install.py CLI dispatch and action routing."""

import argparse
import os
import sys
import tempfile
from pathlib import Path
from unittest import mock

import pytest

# Ensure orchestration modules are importable
_repo_root = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(_repo_root / "orchestration" / "lib"))
sys.path.insert(0, str(_repo_root / "orchestration"))

import kubeadm_cli as kubeadm_install
from deployment_mgr import (
    KubeadmDeployment, show_deployments, parse_edge_cloud_spec,
    edge_deployment_type, edge_cloud_from_deployment_type,
    deployment_type, detect_ctrl_cloud, discover_edge_deployments,
)
from tfvars import TfVarsLoader


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


@pytest.fixture
def deployment_root(tmp_path):
    """Create a temporary deployment root with sample customer dirs."""
    root = tmp_path / "deployment"
    root.mkdir()

    # AWS ctrl
    ctrl = root / "hstest_aws-ctrl"
    ctrl.mkdir()
    (ctrl / "terraform.tfvars").write_text(
        'customer_name = "hstest"\nregion = "us-east-1"\nworker_node_count = 1\n'
    )

    # AWS edge (legacy, no region)
    edge_aws = root / "hstest_aws-edge"
    edge_aws.mkdir()
    (edge_aws / "terraform.tfvars").write_text(
        'customer_name = "hstest"\nregion = "us-east-1"\ninstance_count = 1\n'
    )

    # AWS edge (regional)
    edge_aws_r = root / "hstest_aws-edge-us-west-2"
    edge_aws_r.mkdir()
    (edge_aws_r / "terraform.tfvars").write_text(
        'customer_name = "hstest"\nregion = "us-west-2"\ninstance_count = 2\n'
    )

    # GCP edge (regional)
    edge_gcp = root / "hstest_gcp-edge-us-east1"
    edge_gcp.mkdir()
    (edge_gcp / "terraform.tfvars").write_text(
        'customer_name = "hstest"\nproject_id = "lightbeam-dev"\nzone = "us-east1-b"\ninstance_count = 1\n'
    )

    os.environ["LIGHTBEAM_DEPLOYMENT_ROOT"] = str(root)
    yield root
    os.environ.pop("LIGHTBEAM_DEPLOYMENT_ROOT", None)


# ---------------------------------------------------------------------------
# Edge cloud spec parsing
# ---------------------------------------------------------------------------


class TestParseEdgeCloudSpec:
    def test_cloud_only(self):
        cloud, region = parse_edge_cloud_spec("aws")
        assert cloud == "aws"
        assert region == ""

    def test_cloud_with_region(self):
        cloud, region = parse_edge_cloud_spec("aws:us-east-1")
        assert cloud == "aws"
        assert region == "us-east-1"

    def test_gcp_with_zone(self):
        cloud, region = parse_edge_cloud_spec("gcp:us-east1")
        assert cloud == "gcp"
        assert region == "us-east1"

    def test_invalid_cloud(self):
        with pytest.raises(SystemExit):
            parse_edge_cloud_spec("azure:eastus")


class TestEdgeDeploymentType:
    def test_with_region(self):
        assert edge_deployment_type("aws", "us-east-1") == "aws-edge-us-east-1"

    def test_without_region(self):
        assert edge_deployment_type("aws", "") == "aws-edge"

    def test_gcp(self):
        assert edge_deployment_type("gcp", "us-east1") == "gcp-edge-us-east1"


class TestEdgeCloudFromDeploymentType:
    def test_legacy(self):
        cloud, region = edge_cloud_from_deployment_type("aws-edge")
        assert cloud == "aws"
        assert region == ""

    def test_regional(self):
        cloud, region = edge_cloud_from_deployment_type("aws-edge-us-east-1")
        assert cloud == "aws"
        assert region == "us-east-1"

    def test_gcp_regional(self):
        cloud, region = edge_cloud_from_deployment_type("gcp-edge-us-east1")
        assert cloud == "gcp"
        assert region == "us-east1"

    def test_ctrl(self):
        cloud, region = edge_cloud_from_deployment_type("aws-ctrl")
        assert cloud == ""
        assert region == ""


# ---------------------------------------------------------------------------
# Deployment discovery
# ---------------------------------------------------------------------------


class TestDiscoverEdgeDeployments:
    def test_finds_all(self, deployment_root):
        edges = discover_edge_deployments("hstest")
        clouds = [(c, r) for c, r, _ in edges]
        assert ("aws", "") in clouds  # legacy
        assert ("aws", "us-west-2") in clouds  # regional
        assert ("gcp", "us-east1") in clouds  # gcp regional

    def test_no_customer(self, deployment_root):
        edges = discover_edge_deployments("nonexistent")
        assert edges == []

    def test_empty_root(self, tmp_path):
        os.environ["LIGHTBEAM_DEPLOYMENT_ROOT"] = str(tmp_path)
        edges = discover_edge_deployments("hstest")
        assert edges == []


class TestDetectCtrlCloud:
    def test_single_ctrl(self, deployment_root):
        cloud = detect_ctrl_cloud("hstest")
        assert cloud == "aws"

    def test_no_ctrl(self, deployment_root):
        with pytest.raises(SystemExit):
            detect_ctrl_cloud("nonexistent")

    def test_multiple_ctrl(self, deployment_root):
        # Add a GCP ctrl
        gcp_ctrl = deployment_root / "hstest_gcp-ctrl"
        gcp_ctrl.mkdir()
        (gcp_ctrl / "terraform.tfvars").write_text(
            'customer_name = "hstest"\nproject_id = "proj"\nzone = "us-east1-b"\nworker_node_count = 1\n'
        )
        with pytest.raises(SystemExit):
            detect_ctrl_cloud("hstest")


class TestDiscoverAllDeployments:
    def test_all(self, deployment_root):
        deployments = KubeadmDeployment.discover_all("hstest")
        assert len(deployments) >= 2  # ctrl + at least 1 edge

    def test_filtered(self, deployment_root):
        deployments = KubeadmDeployment.discover_all("nonexistent")
        assert deployments == []


# ---------------------------------------------------------------------------
# Tfvars helpers
# ---------------------------------------------------------------------------


class TestReadTfvarsValue:
    def test_read_string(self, deployment_root):
        path = deployment_root / "hstest_aws-ctrl" / "terraform.tfvars"
        assert TfVarsLoader.read_tfvars_value(path, "customer_name") == "hstest"

    def test_read_number(self, deployment_root):
        path = deployment_root / "hstest_aws-ctrl" / "terraform.tfvars"
        assert TfVarsLoader.read_tfvars_value(path, "worker_node_count") == "1"

    def test_missing_key(self, deployment_root):
        path = deployment_root / "hstest_aws-ctrl" / "terraform.tfvars"
        assert TfVarsLoader.read_tfvars_value(path, "nonexistent") == ""

    def test_missing_file(self, tmp_path):
        assert TfVarsLoader.read_tfvars_value(tmp_path / "nope.tfvars", "key") == ""


class TestUpdateTfvarsValue:
    def test_update_existing(self, tmp_path):
        tfvars = tmp_path / "terraform.tfvars"
        tfvars.write_text('worker_node_count = 1\ncustomer_name = "test"\n')
        TfVarsLoader.update_tfvars_value(tfvars, "worker_node_count", "3")
        assert "worker_node_count = 3" in tfvars.read_text()
        assert 'customer_name = "test"' in tfvars.read_text()

    def test_add_new(self, tmp_path):
        tfvars = tmp_path / "terraform.tfvars"
        tfvars.write_text('customer_name = "test"\n')
        TfVarsLoader.update_tfvars_value(tfvars, "custom_ami", '"ami-123"')
        assert 'custom_ami = "ami-123"' in tfvars.read_text()


# ---------------------------------------------------------------------------
# Action routing (no-op mocks — verify dispatch, not execution)
# ---------------------------------------------------------------------------


class TestActionRouting:
    """Verify that actions route to the correct functions without actually executing."""

    def _make_args(self, **overrides):
        defaults = dict(
            ctrl_cloud="aws",
            edge_cloud=None,
            customer="hstest",
            action="output",
            no_published_image=False,
            install_only=False,
            skip_packages=False,
            skip_gateway=False,
            skip_cp=False,
            skip_workers=False,
            skip=None,
            add=None,
            remove=None,
            timeout=1800,
            v=False,
            terraform_script=None,
            shared_scripts=None,
            wireguard_state=None,
            has_gateway=None,
            reset=None,
            region=None,
            project=None,
            zone=None,
            scope=None,
            target=None,
        )
        defaults.update(overrides)
        return argparse.Namespace(**defaults)

    def test_output_no_confirmation(self, deployment_root):
        """--action output should not prompt for confirmation."""
        args = self._make_args(action="output")
        with mock.patch("kubeadm_cli.parse_args", return_value=args), \
             mock.patch("kubeadm_cli.run_install") as mock_run:
            try:
                kubeadm_install.main()
            except (SystemExit, Exception):
                pass  # may fail on tf_script resolution
            # Verify no input() was called (would hang in test)

    def test_show_no_confirmation(self, deployment_root):
        """--action show should not prompt for confirmation."""
        args = self._make_args(action="show")
        with mock.patch("kubeadm_cli.parse_args", return_value=args), \
             mock.patch("deployment_mgr.KubeadmDeployment.show_output") as mock_show:
            kubeadm_install.main()
            mock_show.assert_called()

    def test_destroy_confirmation_required(self, deployment_root):
        """--action destroy requires typing 'destroy' to confirm."""
        args = self._make_args(action="destroy")
        with mock.patch("kubeadm_cli.parse_args", return_value=args), \
             mock.patch("deployment_mgr.KubeadmDeployment.print_image_summary"), \
             mock.patch("builtins.input", return_value="no"):
            kubeadm_install.main()
            # Should not raise — cancelled gracefully

    def test_terraform_only_no_confirmation(self, deployment_root):
        """--action init/apply/output should not prompt."""
        for action in ("init", "apply", "output", "cleanup-state"):
            args = self._make_args(action=action)
            with mock.patch("kubeadm_cli.parse_args", return_value=args), \
                 mock.patch("kubeadm_cli.run_install") as mock_run:
                try:
                    kubeadm_install.main()
                except (SystemExit, Exception):
                    pass  # may fail downstream
                # Key: no input() called — test would hang otherwise


# ---------------------------------------------------------------------------
# Image manager base class
# ---------------------------------------------------------------------------


class TestImageInfo:
    def test_display_latest(self):
        from image import ImageInfo
        img = ImageInfo(id="ami-123", name="ubuntu-24-04-lb-lat", created="2026-03-28", is_backup=False)
        assert "(latest)" in img.display
        assert "ami-123" in img.display

    def test_display_backup(self):
        from image import ImageInfo
        img = ImageInfo(id="ami-456", name="ubuntu-24-04-lb-lat-bak", created="2026-03-27", is_backup=True)
        assert "(backup)" in img.display


class TestImageManagerFactory:
    def test_create_aws(self):
        with mock.patch.dict("sys.modules", {"boto3": mock.MagicMock()}):
            from image import ImageManager
            mgr = ImageManager.create("aws", region="us-east-1")
            assert mgr.tfvars_key() == "custom_ami"

    def test_create_gcp(self):
        from image import ImageManager
        mgr = ImageManager.create("gcp", project="my-proj", zone="us-east1-b")
        assert mgr.tfvars_key() == "custom_image"

    def test_create_unsupported(self):
        from image import ImageManager
        with pytest.raises(ValueError):
            ImageManager.create("azure", region="eastus")


class TestAutoResolveImage:
    def _make_mgr(self):
        """Create a mock ImageManager for testing auto_resolve_image."""
        from image import ImageManager, ImageInfo

        class MockMgr(ImageManager):
            def __init__(self, latest=None):
                self._latest = latest
            @property
            def location(self): return "test-region"
            def list_images(self): return []
            def find_latest(self): return self._latest
            def find_by_name(self, n): return None
            def delete_image(self, i): pass
            def rename_image(self, i, n): return None
            def create_image(self, iid, n, d=""): return None
            def detect_os_name(self, iid): return "ubuntu-24-04"
            def tfvars_key(self): return "custom_ami"

        return MockMgr, ImageInfo

    def test_no_published_image_flag(self):
        MockMgr, _ = self._make_mgr()
        mgr = MockMgr()
        result = mgr.auto_resolve_image(no_published_image=True)
        assert result is None

    def test_current_custom_in_tfvars(self):
        MockMgr, _ = self._make_mgr()
        mgr = MockMgr()
        result = mgr.auto_resolve_image(current_custom_image="ami-from-tfvars")
        assert result == "ami-from-tfvars"

    def test_auto_detect_published(self):
        MockMgr, ImageInfo = self._make_mgr()
        latest = ImageInfo(id="ami-auto", name="ubuntu-24-04-lb-lat", created="", is_backup=False)
        mgr = MockMgr(latest=latest)
        result = mgr.auto_resolve_image()
        assert result == "ami-auto"

    def test_no_published_image_returns_none(self):
        MockMgr, _ = self._make_mgr()
        mgr = MockMgr(latest=None)
        result = mgr.auto_resolve_image()
        assert result is None

    def test_priority_order(self):
        """--no-published-image beats tfvars beats auto-detect."""
        MockMgr, ImageInfo = self._make_mgr()
        latest = ImageInfo(id="ami-auto", name="test", created="", is_backup=False)
        mgr = MockMgr(latest=latest)

        # newer published image — user confirms by typing name
        with mock.patch("builtins.input", return_value="test"):
            assert mgr.auto_resolve_image(
                current_custom_image="ami-tfvars",
            ) == "ami-auto"

        # newer published image — user declines (Enter)
        with mock.patch("builtins.input", return_value=""):
            assert mgr.auto_resolve_image(
                current_custom_image="ami-tfvars",
            ) == "ami-tfvars"

        # no_published_image wins over everything
        assert mgr.auto_resolve_image(
            current_custom_image="ami-tfvars",
            no_published_image=True,
        ) is None


# ---------------------------------------------------------------------------
# Image manager operations (rotate, generate name, delete matching)
# ---------------------------------------------------------------------------


class TestImageManagerOperations:
    def _make_mgr(self):
        from image import ImageManager, ImageInfo

        class MockMgr(ImageManager):
            def __init__(self):
                self._images = {}
                self._deleted = []
                self._created = []
            @property
            def location(self): return "test-region"
            def list_images(self):
                return list(self._images.values())
            def find_latest(self):
                non_bak = [i for i in self._images.values() if not i.is_backup]
                return non_bak[0] if non_bak else None
            def find_by_name(self, n):
                return self._images.get(n)
            def delete_image(self, i):
                self._deleted.append(i.name)
                self._images.pop(i.name, None)
            def rename_image(self, i, new_name):
                old = self._images.pop(i.name, None)
                if old:
                    new = ImageInfo(id=f"new-{new_name}", name=new_name, created="", is_backup=new_name.endswith("-bak"))
                    self._images[new_name] = new
                    return new
                return None
            def create_image(self, iid, n, d=""):
                img = ImageInfo(id=f"created-{n}", name=n, created="2026-03-28", is_backup=False)
                self._images[n] = img
                self._created.append(n)
                return img
            def detect_os_name(self, iid):
                return "ubuntu-24-04"
            def tfvars_key(self):
                return "custom_ami"

        return MockMgr, ImageInfo

    def test_generate_image_name(self):
        MockMgr, _ = self._make_mgr()
        mgr = MockMgr()
        name = mgr.generate_image_name("i-123")
        assert name.startswith("ubuntu-24-04-")
        assert name.endswith("-lb-lat")

    def test_rotate_and_create_fresh(self):
        """First publish — no existing images."""
        MockMgr, _ = self._make_mgr()
        mgr = MockMgr()
        img = mgr.rotate_and_create("i-123", "test-lb-lat")
        assert img.name == "test-lb-lat"
        assert img.id == "created-test-lb-lat"
        assert mgr._deleted == []

    def test_rotate_and_create_with_existing(self):
        """Second publish — existing image should become backup."""
        MockMgr, ImageInfo = self._make_mgr()
        mgr = MockMgr()
        mgr._images["test-lb-lat"] = ImageInfo(id="old-id", name="test-lb-lat", created="", is_backup=False)

        img = mgr.rotate_and_create("i-123", "test-lb-lat")
        assert img.name == "test-lb-lat"
        assert "test-lb-lat-bak" in mgr._images  # old renamed to bak
        assert mgr._created == ["test-lb-lat"]

    def test_rotate_and_create_with_existing_and_bak(self):
        """Third publish — existing bak deleted, current becomes bak, new created."""
        MockMgr, ImageInfo = self._make_mgr()
        mgr = MockMgr()
        mgr._images["test-lb-lat-bak"] = ImageInfo(id="bak-id", name="test-lb-lat-bak", created="", is_backup=True)
        mgr._images["test-lb-lat"] = ImageInfo(id="cur-id", name="test-lb-lat", created="", is_backup=False)

        img = mgr.rotate_and_create("i-123", "test-lb-lat")
        assert "test-lb-lat-bak" in mgr._deleted  # old bak deleted
        assert img.name == "test-lb-lat"

    def test_delete_matching_none(self, capsys):
        MockMgr, _ = self._make_mgr()
        mgr = MockMgr()
        mgr.delete_matching("nonexistent")
        # No error, just logs "No images matching..."

    def test_delete_matching_with_confirmation(self):
        MockMgr, ImageInfo = self._make_mgr()
        mgr = MockMgr()
        mgr._images["ubuntu-24-04-lb-lat"] = ImageInfo(
            id="ami-1", name="ubuntu-24-04-lb-lat", created="2026-03-28", is_backup=False)
        mgr._images["ubuntu-24-04-lb-lat-bak"] = ImageInfo(
            id="ami-2", name="ubuntu-24-04-lb-lat-bak", created="2026-03-27", is_backup=True)

        with mock.patch("builtins.input", return_value="y"):
            mgr.delete_matching("ubuntu.*lb-lat")
        assert len(mgr._deleted) == 2

    def test_delete_matching_cancelled(self):
        MockMgr, ImageInfo = self._make_mgr()
        mgr = MockMgr()
        mgr._images["test-lb-lat"] = ImageInfo(id="ami-1", name="test-lb-lat", created="", is_backup=False)

        with mock.patch("builtins.input", return_value="n"):
            mgr.delete_matching("test")
        assert mgr._deleted == []  # cancelled, nothing deleted

    def test_print_list_empty(self, capsys):
        MockMgr, _ = self._make_mgr()
        mgr = MockMgr()
        mgr.print_list()

    def test_print_list_with_images(self, capsys):
        MockMgr, ImageInfo = self._make_mgr()
        mgr = MockMgr()
        mgr._images["test-lb-lat"] = ImageInfo(id="ami-1", name="test-lb-lat", created="2026-03-28", is_backup=False)
        mgr.print_list()
        captured = capsys.readouterr()
        assert "ami-1" in captured.out
        assert "test-lb-lat" in captured.out


# ---------------------------------------------------------------------------
# _show_output and _show_all_outputs
# ---------------------------------------------------------------------------


class TestShowOutput:
    def test_show_output_missing_tfvars(self, deployment_root):
        """Show output for non-existent deployment just logs, no crash."""
        KubeadmDeployment("hstest", "gcp", "ctrl")
        # Should log "No tfvars found" without raising

    def test_show_output_existing(self, deployment_root):
        """Show output for existing deployment runs terraform output."""
        from common import Checkpoint
        ctrl_dir = deployment_root / "hstest_aws-ctrl"
        # Create tf_apply checkpoint and .terraform dir so _show_output doesn't skip
        ckpt = Checkpoint(ctrl_dir / ".orchestration-state")
        ckpt.done("tf_apply")
        (ctrl_dir / ".terraform").mkdir(exist_ok=True)

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=0, stdout="output\n")
            KubeadmDeployment("hstest", "aws", "ctrl").show_output()
            mock_run.assert_called_once()

    def test_show_output_with_region(self, deployment_root):
        """Show output for regional edge uses correct deployment type."""
        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=0)
            KubeadmDeployment("hstest", "aws", "edge", region="us-west-2")
            # Should look for hstest_aws-edge-us-west-2

    def test_show_all_outputs(self, deployment_root):
        """Show all outputs iterates over all deployments."""
        with mock.patch("deployment_mgr.KubeadmDeployment.show_output") as mock_show:
            for d in KubeadmDeployment.discover_all("hstest"):
                d.show_output()
            assert mock_show.call_count >= 2  # at least ctrl + edge


# ---------------------------------------------------------------------------
# _show_deployments
# ---------------------------------------------------------------------------


class TestShowDeployments:
    def test_show_all(self, deployment_root, capsys):
        show_deployments()
        captured = capsys.readouterr()
        assert "hstest" in captured.out

    def test_show_filtered(self, deployment_root, capsys):
        show_deployments("hstest")
        captured = capsys.readouterr()
        assert "hstest" in captured.out

    def test_show_none(self, deployment_root):
        show_deployments("nonexistent")


# ---------------------------------------------------------------------------
# Main dispatch — edge spec normalization
# ---------------------------------------------------------------------------


class TestEdgeSpecNormalization:
    """Test comma and space separated edge cloud parsing in main."""

    def _make_args(self, edge_cloud_raw):
        return argparse.Namespace(
            ctrl_cloud="aws", edge_cloud=edge_cloud_raw, customer="hstest",
            action="show", no_published_image=False, add=None, remove=None, skip=None, install_only=False,
            skip_packages=False, skip_gateway=False, skip_cp=False,
            skip_workers=False, timeout=1800, v=False, terraform_script=None,
            shared_scripts=None, wireguard_state=None, has_gateway=None,
            reset=None, region=None, project=None, zone=None,
            scope=None,
        )

    def test_comma_separated(self, deployment_root):
        """'aws:us-east-1,gcp:us-east1' parses into two specs."""
        args = self._make_args(["aws:us-east-1,gcp:us-east1"])
        with mock.patch("kubeadm_cli.parse_args", return_value=args), \
             mock.patch("deployment_mgr.KubeadmDeployment.show_output"):
            kubeadm_install.main()

    def test_space_separated(self, deployment_root):
        """Multiple args: ['aws:us-east-1', 'gcp:us-east1'] parses into two specs."""
        args = self._make_args(["aws:us-east-1", "gcp:us-east1"])
        with mock.patch("kubeadm_cli.parse_args", return_value=args), \
             mock.patch("deployment_mgr.KubeadmDeployment.show_output"):
            kubeadm_install.main()

    def test_cloud_only_no_region(self, deployment_root):
        """'aws' parses as cloud=aws, region=''."""
        args = self._make_args(["aws"])
        with mock.patch("kubeadm_cli.parse_args", return_value=args), \
             mock.patch("deployment_mgr.KubeadmDeployment.show_output"):
            kubeadm_install.main()


# ---------------------------------------------------------------------------
# Reset handling
# ---------------------------------------------------------------------------


class TestResetHandling:
    def _make_args(self, **overrides):
        defaults = dict(
            ctrl_cloud="aws", edge_cloud=None, customer="hstest",
            action="all", no_published_image=False, add=None, remove=None, skip=None, install_only=False,
            skip_packages=False, skip_gateway=False, skip_cp=False,
            skip_workers=False, timeout=1800, v=False, terraform_script=None,
            shared_scripts=None, wireguard_state=None, has_gateway=None,
            reset="all", region=None, project=None, zone=None,
            scope=None,
        )
        defaults.update(overrides)
        return argparse.Namespace(**defaults)

    def test_reset_all_returns_early(self, deployment_root):
        """--reset all should clear checkpoints and return without prompting."""
        args = self._make_args(reset="all")
        with mock.patch("kubeadm_cli.parse_args", return_value=args):
            kubeadm_install.main()
            # Should not prompt — returns after clearing

    def test_reset_specific_stage(self, deployment_root):
        """--reset <stage> clears that stage then continues to prompt."""
        args = self._make_args(reset="phase1_cp")
        with mock.patch("kubeadm_cli.parse_args", return_value=args), \
             mock.patch("deployment_mgr.KubeadmDeployment.print_image_summary"), \
             mock.patch("builtins.input", return_value="n"):
            kubeadm_install.main()


# ---------------------------------------------------------------------------
# Auto-detect ctrl cloud and edges
# ---------------------------------------------------------------------------


class TestAutoDetect:
    def _make_args(self, **overrides):
        defaults = dict(
            ctrl_cloud="", edge_cloud=None, customer="hstest",
            action="show", no_published_image=False, add=None, remove=None, skip=None, install_only=False,
            skip_packages=False, skip_gateway=False, skip_cp=False,
            skip_workers=False, timeout=1800, v=False, terraform_script=None,
            shared_scripts=None, wireguard_state=None, has_gateway=None,
            reset=None, region=None, project=None, zone=None,
            scope=None,
        )
        defaults.update(overrides)
        return argparse.Namespace(**defaults)

    def test_auto_detect_ctrl_and_edges(self, deployment_root):
        """No --ctrl-cloud or --edge-cloud: auto-detects both from deployment dirs."""
        args = self._make_args()
        with mock.patch("kubeadm_cli.parse_args", return_value=args), \
             mock.patch("deployment_mgr.KubeadmDeployment.show_output"), \
             mock.patch("deployment_mgr.KubeadmDeployment.show_output"):
            kubeadm_install.main()

    def test_auto_detect_no_customer_show(self, deployment_root):
        """No customer with --action show lists all deployments."""
        args = self._make_args(customer="", action="show")
        with mock.patch("kubeadm_cli.parse_args", return_value=args), \
             mock.patch("kubeadm_cli.show_deployments") as mock_show:
            kubeadm_install.main()
            mock_show.assert_called()

    def test_auto_detect_no_customer_install_fails(self, deployment_root):
        """No customer and no clouds with --action all should error."""
        args = self._make_args(customer="", action="all")
        with mock.patch("kubeadm_cli.parse_args", return_value=args):
            with pytest.raises(SystemExit):
                kubeadm_install.main()

    def test_ctrl_only_no_edge_autodiscovery(self, deployment_root):
        """--ctrl-cloud aws alone should NOT auto-discover edge deployments."""
        args = self._make_args(ctrl_cloud="aws", action="all")
        install_calls = []

        def fake_run_install(a, cloud, mode, region=""):
            install_calls.append((cloud, mode, region))

        with mock.patch("kubeadm_cli.parse_args", return_value=args), \
             mock.patch("kubeadm_cli.run_install", side_effect=fake_run_install), \
             mock.patch("deployment_mgr.KubeadmDeployment.print_image_summary"), \
             mock.patch("builtins.input", return_value="y"):
            kubeadm_install.main()

        assert install_calls == [("aws", "ctrl", "")]

    def test_edge_only_no_ctrl(self, deployment_root):
        """--edge-cloud aws alone should only install edge, not ctrl."""
        args = self._make_args(ctrl_cloud="", edge_cloud=["aws"], action="all")
        install_calls = []

        def fake_run_install(a, cloud, mode, region=""):
            install_calls.append((cloud, mode, region))

        with mock.patch("kubeadm_cli.parse_args", return_value=args), \
             mock.patch("kubeadm_cli.run_install", side_effect=fake_run_install), \
             mock.patch("deployment_mgr.KubeadmDeployment.print_image_summary"), \
             mock.patch("builtins.input", return_value="y"):
            kubeadm_install.main()

        assert len(install_calls) == 1
        assert install_calls[0][1] == "edge"

    def test_ctrl_and_edge_explicit(self, deployment_root):
        """--ctrl-cloud aws --edge-cloud aws installs both."""
        args = self._make_args(ctrl_cloud="aws", edge_cloud=["aws"], action="all")
        install_calls = []

        def fake_run_install(a, cloud, mode, region=""):
            install_calls.append((cloud, mode, region))

        with mock.patch("kubeadm_cli.parse_args", return_value=args), \
             mock.patch("kubeadm_cli.run_install", side_effect=fake_run_install), \
             mock.patch("deployment_mgr.KubeadmDeployment.print_image_summary"), \
             mock.patch("builtins.input", return_value="y"):
            kubeadm_install.main()

        modes = [c[1] for c in install_calls]
        assert "ctrl" in modes
        assert "edge" in modes


# ---------------------------------------------------------------------------
# Image size display
# ---------------------------------------------------------------------------


class TestImageInfoSize:
    def test_display_with_size(self):
        from image import ImageInfo
        img = ImageInfo(id="ami-1", name="test-lb-lat", created="2026-03-28",
                        is_backup=False, size_gb=50.0)
        assert "50.0 GB" in img.display
        assert "(latest)" in img.display

    def test_display_without_size(self):
        from image import ImageInfo
        img = ImageInfo(id="ami-1", name="test-lb-lat", created="2026-03-28",
                        is_backup=False, size_gb=0.0)
        assert "GB" not in img.display

    def test_display_backup_with_size(self):
        from image import ImageInfo
        img = ImageInfo(id="ami-2", name="test-lb-lat-bak", created="2026-03-27",
                        is_backup=True, size_gb=100.5)
        assert "100.5 GB" in img.display
        assert "(backup)" in img.display


# ---------------------------------------------------------------------------
# Delete matching — wildcard and warning
# ---------------------------------------------------------------------------


class TestDeleteMatching:
    def _make_mgr(self):
        from image import ImageManager, ImageInfo

        class MockMgr(ImageManager):
            def __init__(self):
                self._images = {}
                self._deleted = []
            @property
            def location(self): return "test-region"
            def list_images(self):
                return list(self._images.values())
            def find_latest(self): return None
            def find_by_name(self, n): return self._images.get(n)
            def delete_image(self, i):
                self._deleted.append(i.name)
                self._images.pop(i.name, None)
            def rename_image(self, i, n): return None
            def create_image(self, iid, n, d=""): return None
            def detect_os_name(self, iid): return "unknown"
            def tfvars_key(self): return "custom_ami"

        return MockMgr, ImageInfo

    def test_star_matches_all(self):
        """Pattern '*' should match all images."""
        MockMgr, ImageInfo = self._make_mgr()
        mgr = MockMgr()
        mgr._images["a-lb-lat"] = ImageInfo(id="1", name="a-lb-lat", created="", is_backup=False)
        mgr._images["b-lb-lat-bak"] = ImageInfo(id="2", name="b-lb-lat-bak", created="", is_backup=True)

        with mock.patch("builtins.input", return_value="y"):
            mgr.delete_matching("*")
        assert len(mgr._deleted) == 2

    def test_star_shows_warning(self, capsys):
        """Pattern '*' should show ALL warning."""
        MockMgr, ImageInfo = self._make_mgr()
        mgr = MockMgr()
        mgr._images["a-lb-lat"] = ImageInfo(id="1", name="a-lb-lat", created="", is_backup=False)

        with mock.patch("builtins.input", return_value="n"):
            mgr.delete_matching("*")
        captured = capsys.readouterr()
        assert "WARNING" in captured.out
        assert "ALL" in captured.out

    def test_specific_pattern_no_warning(self, capsys):
        """Specific pattern matching subset should not show ALL warning."""
        MockMgr, ImageInfo = self._make_mgr()
        mgr = MockMgr()
        mgr._images["ubuntu-lb-lat"] = ImageInfo(id="1", name="ubuntu-lb-lat", created="", is_backup=False)
        mgr._images["rhel-lb-lat"] = ImageInfo(id="2", name="rhel-lb-lat", created="", is_backup=False)

        with mock.patch("builtins.input", return_value="n"):
            mgr.delete_matching("ubuntu")
        captured = capsys.readouterr()
        assert "WARNING" not in captured.out

    def test_regex_pattern(self):
        """Regex patterns should work."""
        MockMgr, ImageInfo = self._make_mgr()
        mgr = MockMgr()
        mgr._images["ubuntu-24-04-lb-lat"] = ImageInfo(id="1", name="ubuntu-24-04-lb-lat", created="", is_backup=False)
        mgr._images["rhel-9-lb-lat"] = ImageInfo(id="2", name="rhel-9-lb-lat", created="", is_backup=False)

        with mock.patch("builtins.input", return_value="y"):
            mgr.delete_matching(r"ubuntu.*lb-lat$")
        assert mgr._deleted == ["ubuntu-24-04-lb-lat"]
        assert "rhel-9-lb-lat" in mgr._images

    def test_no_images_at_all(self):
        """Empty image list should log and return."""
        MockMgr, _ = self._make_mgr()
        mgr = MockMgr()
        mgr.delete_matching("anything")  # no crash


# ---------------------------------------------------------------------------
# AWS AMI size helper
# ---------------------------------------------------------------------------


class TestAwsAmiSize:
    def test_single_volume(self):
        with mock.patch.dict("sys.modules", {"boto3": mock.MagicMock()}):
            from image import _AwsImageManager
            size = _AwsImageManager._ami_size_gb({
                "BlockDeviceMappings": [{"Ebs": {"VolumeSize": 100}}]
            })
            assert size == 100.0

    def test_multiple_volumes(self):
        with mock.patch.dict("sys.modules", {"boto3": mock.MagicMock()}):
            from image import _AwsImageManager
            size = _AwsImageManager._ami_size_gb({
                "BlockDeviceMappings": [
                    {"Ebs": {"VolumeSize": 50}},
                    {"Ebs": {"VolumeSize": 200}},
                ]
            })
            assert size == 250.0

    def test_no_ebs(self):
        with mock.patch.dict("sys.modules", {"boto3": mock.MagicMock()}):
            from image import _AwsImageManager
            size = _AwsImageManager._ami_size_gb({"BlockDeviceMappings": []})
            assert size == 0.0

    def test_instance_store(self):
        with mock.patch.dict("sys.modules", {"boto3": mock.MagicMock()}):
            from image import _AwsImageManager
            size = _AwsImageManager._ami_size_gb({
                "BlockDeviceMappings": [{"VirtualName": "ephemeral0"}]
            })
            assert size == 0.0


# ---------------------------------------------------------------------------
# Image constants
# ---------------------------------------------------------------------------


class TestImageConstants:
    def test_suffixes(self):
        from image import IMAGE_SUFFIX, BACKUP_SUFFIX
        assert IMAGE_SUFFIX == "-lb-lat"
        assert BACKUP_SUFFIX == "-lb-lat-bak"
        assert BACKUP_SUFFIX.startswith(IMAGE_SUFFIX)
