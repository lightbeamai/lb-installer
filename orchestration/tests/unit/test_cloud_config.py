"""Tests for cloud_config — CtrlCloudConfig and EdgeCloudConfig."""

import sys
import tempfile
from pathlib import Path

import pytest

_repo_root = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(_repo_root / "orchestration" / "lib"))
sys.path.insert(0, str(_repo_root / "orchestration"))

from cloud_config import (
    AWS_CTRL, GCP_CTRL, AWS_EDGE, GCP_EDGE,
    get_ctrl_config, get_edge_config,
)


class TestCtrlConfig:
    def test_aws_ctrl_defaults(self):
        cfg = get_ctrl_config("aws")
        assert cfg.cloud == "aws"
        assert cfg.has_gateway is True
        assert cfg.cp_type_default == "t3.small"
        assert cfg.worker_type_default == "m6i.2xlarge"
        assert cfg.worker_data_disk_default == "500"

    def test_gcp_ctrl_defaults(self):
        cfg = get_ctrl_config("gcp")
        assert cfg.cloud == "gcp"
        assert cfg.has_gateway is False
        assert cfg.cp_type_default == "e2-standard-8"
        assert cfg.worker_type_default == "e2-standard-8"

    def test_unknown_cloud_raises(self):
        with pytest.raises(ValueError):
            get_ctrl_config("azure")

    def test_read_from_tfvars(self, tmp_path):
        tfvars = tmp_path / "terraform.tfvars"
        tfvars.write_text('control_plane_instance_type = "t3.medium"\nworker_node_count = 5\n')
        cfg = get_ctrl_config("aws")
        assert cfg.read(tfvars, "cp_type_key") == "t3.medium"
        assert cfg.read(tfvars, "worker_count_key") == "5"

    def test_read_uses_default(self, tmp_path):
        tfvars = tmp_path / "terraform.tfvars"
        tfvars.write_text('customer_name = "test"\n')
        cfg = get_ctrl_config("aws")
        assert cfg.read(tfvars, "cp_type_key") == "t3.small"  # default

    def test_disk_summary_aws(self, tmp_path):
        tfvars = tmp_path / "terraform.tfvars"
        tfvars.write_text('worker_root_disk_size_gb = 100\nworker_ebs_volume_size = 500\n')
        cfg = get_ctrl_config("aws")
        summary = cfg.disk_summary(tfvars, "worker")
        assert "100" in summary
        assert "500" in summary
        assert "EBS" in summary

    def test_disk_summary_gcp(self, tmp_path):
        tfvars = tmp_path / "terraform.tfvars"
        tfvars.write_text('worker_boot_disk_size_gb = 100\nworker_disk_size_gb = 500\n')
        cfg = get_ctrl_config("gcp")
        summary = cfg.disk_summary(tfvars, "worker")
        assert "100" in summary
        assert "500" in summary
        assert "data" in summary


class TestEdgeConfig:
    def test_aws_edge_defaults(self):
        cfg = get_edge_config("aws")
        assert cfg.cloud == "aws"
        assert cfg.type_default == "m6i.4xlarge"
        assert cfg.disk_default == "100"
        assert cfg.count_key == "instance_count"

    def test_gcp_edge_defaults(self):
        cfg = get_edge_config("gcp")
        assert cfg.cloud == "gcp"
        assert cfg.type_default == "e2-standard-16"

    def test_unknown_cloud_raises(self):
        with pytest.raises(ValueError):
            get_edge_config("azure")

    def test_read_from_tfvars(self, tmp_path):
        tfvars = tmp_path / "terraform.tfvars"
        tfvars.write_text('instance_count = 3\ninstance_type = "m6i.xlarge"\n')
        cfg = get_edge_config("aws")
        assert cfg.read(tfvars, "count_key") == "3"
        assert cfg.read(tfvars, "type_key") == "m6i.xlarge"
