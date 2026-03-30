"""Tests for deployment_mgr — KubeadmDeployment, discovery, type helpers."""

import os
import sys
from pathlib import Path

import pytest

_repo_root = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(_repo_root / "orchestration" / "lib"))
sys.path.insert(0, str(_repo_root / "orchestration"))

from unittest import mock

from deployment_mgr import (
    deployment_type, edge_deployment_type, edge_cloud_from_deployment_type,
    parse_edge_cloud_spec, KubeadmDeployment, show_deployments,
    detect_ctrl_cloud, discover_edge_deployments,
)
from common import die


@pytest.fixture
def deployment_root(tmp_path):
    root = tmp_path / "deployment"
    root.mkdir()
    ctrl = root / "hstest_aws-ctrl"
    ctrl.mkdir()
    (ctrl / "terraform.tfvars").write_text('customer_name = "hstest"\nregion = "us-east-1"\nworker_node_count = 1\n')
    edge_aws = root / "hstest_aws-edge"
    edge_aws.mkdir()
    (edge_aws / "terraform.tfvars").write_text('customer_name = "hstest"\nregion = "us-east-1"\ninstance_count = 1\n')
    edge_aws_r = root / "hstest_aws-edge-us-west-2"
    edge_aws_r.mkdir()
    (edge_aws_r / "terraform.tfvars").write_text('customer_name = "hstest"\nregion = "us-west-2"\n')
    edge_gcp = root / "hstest_gcp-edge-us-east1"
    edge_gcp.mkdir()
    (edge_gcp / "terraform.tfvars").write_text('customer_name = "hstest"\nproject_id = "dev"\nzone = "us-east1-b"\n')
    os.environ["LIGHTBEAM_DEPLOYMENT_ROOT"] = str(root)
    yield root
    os.environ.pop("LIGHTBEAM_DEPLOYMENT_ROOT", None)


class TestDeploymentType:
    def test_ctrl(self):
        assert deployment_type("aws", "ctrl") == "aws-ctrl"

    def test_edge_no_region(self):
        assert deployment_type("aws", "edge") == "aws-edge"

    def test_edge_with_region(self):
        assert deployment_type("aws", "edge", "us-east-1") == "aws-edge-us-east-1"

    def test_edge_helper(self):
        assert edge_deployment_type("gcp", "us-east1") == "gcp-edge-us-east1"

    def test_edge_helper_no_region(self):
        assert edge_deployment_type("aws", "") == "aws-edge"


class TestEdgeCloudFromDeploymentType:
    def test_legacy(self):
        assert edge_cloud_from_deployment_type("aws-edge") == ("aws", "")

    def test_regional(self):
        assert edge_cloud_from_deployment_type("aws-edge-us-east-1") == ("aws", "us-east-1")

    def test_gcp(self):
        assert edge_cloud_from_deployment_type("gcp-edge-us-east1") == ("gcp", "us-east1")

    def test_ctrl_returns_empty(self):
        assert edge_cloud_from_deployment_type("aws-ctrl") == ("", "")


class TestParseEdgeCloudSpec:
    def test_cloud_only(self):
        assert parse_edge_cloud_spec("aws") == ("aws", "")

    def test_cloud_with_region(self):
        assert parse_edge_cloud_spec("aws:us-east-1") == ("aws", "us-east-1")

    def test_gcp_with_zone(self):
        assert parse_edge_cloud_spec("gcp:us-east1") == ("gcp", "us-east1")

    def test_invalid_cloud(self):
        with pytest.raises(SystemExit):
            parse_edge_cloud_spec("azure:eastus")


class TestKubeadmDeployment:
    def test_init(self, deployment_root):
        d = KubeadmDeployment("hstest", "aws", "ctrl")
        assert d.dt == "aws-ctrl"
        assert d.customer == "hstest"

    def test_status_fresh(self, deployment_root):
        d = KubeadmDeployment("hstest", "aws", "ctrl")
        assert "fresh" in d.status()

    def test_status_after_checkpoint(self, deployment_root):
        from common import Checkpoint
        ctrl = deployment_root / "hstest_aws-ctrl"
        ckpt = Checkpoint(ctrl / ".orchestration-state")
        ckpt.done("tf_init")
        ckpt.done("tf_apply")
        ckpt.done("phase1_cp")
        ckpt.done("phase3_cluster_ready")
        d = KubeadmDeployment("hstest", "aws", "ctrl")
        assert "all phases complete" in d.status()

    def test_discover_edge(self, deployment_root):
        edges = KubeadmDeployment.discover_edge("hstest")
        clouds = {d.cloud for d in edges}
        assert "aws" in clouds

    def test_discover_all(self, deployment_root):
        all_deps = KubeadmDeployment.discover_all("hstest")
        modes = {d.mode for d in all_deps}
        assert "ctrl" in modes
        assert "edge" in modes

    def test_discover_all_nonexistent(self, deployment_root):
        assert KubeadmDeployment.discover_all("nonexistent") == []


class TestShowDeployments:
    def test_shows_all(self, deployment_root, capsys):
        show_deployments("hstest")
        captured = capsys.readouterr()
        assert "hstest" in captured.out

    def test_show_all(self, deployment_root, capsys):
        show_deployments()
        captured = capsys.readouterr()
        assert "hstest" in captured.out

    def test_show_filtered(self, deployment_root, capsys):
        show_deployments("hstest")
        captured = capsys.readouterr()
        assert "hstest" in captured.out

    def test_shows_none(self, deployment_root):
        show_deployments("nonexistent")


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
        gcp_ctrl = deployment_root / "hstest_gcp-ctrl"
        gcp_ctrl.mkdir()
        (gcp_ctrl / "terraform.tfvars").write_text(
            'customer_name = "hstest"\nproject_id = "proj"\nzone = "us-east1-b"\nworker_node_count = 1\n'
        )
        with pytest.raises(SystemExit):
            detect_ctrl_cloud("hstest")


class TestShowOutput:
    def test_show_output_missing_tfvars(self, deployment_root):
        KubeadmDeployment("hstest", "gcp", "ctrl")

    def test_show_output_existing(self, deployment_root):
        from common import Checkpoint
        ctrl_dir = deployment_root / "hstest_aws-ctrl"
        ckpt = Checkpoint(ctrl_dir / ".orchestration-state")
        ckpt.done("tf_apply")
        (ctrl_dir / ".terraform").mkdir(exist_ok=True)

        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=0, stdout="output\n")
            KubeadmDeployment("hstest", "aws", "ctrl").show_output()
            mock_run.assert_called_once()

    def test_show_output_with_region(self, deployment_root):
        with mock.patch("subprocess.run") as mock_run:
            mock_run.return_value = mock.Mock(returncode=0)
            KubeadmDeployment("hstest", "aws", "edge", region="us-west-2")

    def test_show_all_outputs(self, deployment_root):
        with mock.patch("deployment_mgr.KubeadmDeployment.show_output") as mock_show:
            for d in KubeadmDeployment.discover_all("hstest"):
                d.show_output()
            assert mock_show.call_count >= 2
