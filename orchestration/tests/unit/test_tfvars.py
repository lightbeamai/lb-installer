"""Tests for tfvars read/write utilities."""

import sys
from pathlib import Path

import pytest

_repo_root = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(_repo_root / "orchestration" / "lib"))
sys.path.insert(0, str(_repo_root / "orchestration"))

from tfvars import TfVarsLoader


class TestReadTfvarsValue:
    def test_read_string(self, tmp_path):
        f = tmp_path / "terraform.tfvars"
        f.write_text('customer_name = "hstest"\nregion = "us-east-1"\n')
        assert TfVarsLoader.read_tfvars_value(f, "customer_name") == "hstest"
        assert TfVarsLoader.read_tfvars_value(f, "region") == "us-east-1"

    def test_read_number(self, tmp_path):
        f = tmp_path / "terraform.tfvars"
        f.write_text('worker_node_count = 3\n')
        assert TfVarsLoader.read_tfvars_value(f, "worker_node_count") == "3"

    def test_missing_key(self, tmp_path):
        f = tmp_path / "terraform.tfvars"
        f.write_text('region = "us-east-1"\n')
        assert TfVarsLoader.read_tfvars_value(f, "missing_key") == ""

    def test_missing_file(self, tmp_path):
        f = tmp_path / "nonexistent.tfvars"
        assert TfVarsLoader.read_tfvars_value(f, "key") == ""

    def test_comments_ignored(self, tmp_path):
        f = tmp_path / "terraform.tfvars"
        f.write_text('# region = "commented"\nregion = "actual"\n')
        assert TfVarsLoader.read_tfvars_value(f, "region") == "actual"


class TestUpdateTfvarsValue:
    def test_update_existing(self, tmp_path):
        f = tmp_path / "terraform.tfvars"
        f.write_text('region = "us-east-1"\nworker_count = 1\n')
        TfVarsLoader.update_tfvars_value(f, "worker_count", "3")
        assert TfVarsLoader.read_tfvars_value(f, "worker_count") == "3"
        assert TfVarsLoader.read_tfvars_value(f, "region") == "us-east-1"

    def test_add_new(self, tmp_path):
        f = tmp_path / "terraform.tfvars"
        f.write_text('region = "us-east-1"\n')
        TfVarsLoader.update_tfvars_value(f, "new_key", '"new_value"')
        assert TfVarsLoader.read_tfvars_value(f, "new_key") == "new_value"

    def test_quoted_value(self, tmp_path):
        f = tmp_path / "terraform.tfvars"
        f.write_text('instance_type = "t3.small"\n')
        TfVarsLoader.update_tfvars_value(f, "instance_type", '"m6i.xlarge"')
        assert TfVarsLoader.read_tfvars_value(f, "instance_type") == "m6i.xlarge"
