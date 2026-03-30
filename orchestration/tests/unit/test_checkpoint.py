"""Tests for Checkpoint class — persistence, image tracking, clear."""

import sys
from pathlib import Path

import pytest

_repo_root = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(_repo_root / "orchestration" / "lib"))
sys.path.insert(0, str(_repo_root / "orchestration"))

from common import Checkpoint


class TestCheckpointBasic:
    def test_done_creates_file(self, tmp_path):
        ckpt = Checkpoint(tmp_path / ".state")
        ckpt.done("tf_init")
        assert (tmp_path / ".state" / "tf_init.done").exists()

    def test_is_done_false_when_missing(self, tmp_path):
        ckpt = Checkpoint(tmp_path / ".state")
        assert not ckpt.is_done("tf_init")

    def test_is_done_true_after_done(self, tmp_path):
        ckpt = Checkpoint(tmp_path / ".state")
        ckpt.done("phase1_cp")
        assert ckpt.is_done("phase1_cp")

    def test_list_done(self, tmp_path):
        ckpt = Checkpoint(tmp_path / ".state")
        ckpt.done("tf_init")
        ckpt.done("tf_apply")
        ckpt.done("phase1_cp")
        assert ckpt.list_done() == ["phase1_cp", "tf_apply", "tf_init"]

    def test_clear_single(self, tmp_path):
        ckpt = Checkpoint(tmp_path / ".state")
        ckpt.done("tf_init")
        ckpt.done("tf_apply")
        ckpt.clear("tf_apply")
        assert ckpt.is_done("tf_init")
        assert not ckpt.is_done("tf_apply")

    def test_clear_all(self, tmp_path):
        ckpt = Checkpoint(tmp_path / ".state")
        ckpt.done("tf_init")
        ckpt.done("tf_apply")
        ckpt.done("phase1_cp")
        ckpt.clear()
        assert ckpt.list_done() == []

    def test_clear_nonexistent_no_error(self, tmp_path):
        ckpt = Checkpoint(tmp_path / ".state")
        ckpt.clear("nonexistent")  # should not raise

    def test_done_file_contains_timestamp(self, tmp_path):
        ckpt = Checkpoint(tmp_path / ".state")
        ckpt.done("test")
        content = (tmp_path / ".state" / "test.done").read_text()
        assert "202" in content  # year prefix


class TestCheckpointImageTracking:
    def test_done_with_image(self, tmp_path):
        ckpt = Checkpoint(tmp_path / ".state")
        ckpt.done("phase1_cp", image="ami-abc123")
        content = (tmp_path / ".state" / "phase1_cp.done").read_text()
        assert "image: ami-abc123" in content

    def test_is_done_same_image(self, tmp_path):
        ckpt = Checkpoint(tmp_path / ".state")
        ckpt.done("phase1_cp", image="ami-abc123")
        assert ckpt.is_done("phase1_cp", image="ami-abc123")

    def test_is_done_different_image_returns_false(self, tmp_path):
        ckpt = Checkpoint(tmp_path / ".state")
        ckpt.done("phase1_cp", image="ami-old")
        assert not ckpt.is_done("phase1_cp", image="ami-new")

    def test_is_done_no_image_check_always_true(self, tmp_path):
        ckpt = Checkpoint(tmp_path / ".state")
        ckpt.done("phase1_cp", image="ami-old")
        # Without image param, always returns True
        assert ckpt.is_done("phase1_cp")

    def test_is_done_no_stored_image_any_image_true(self, tmp_path):
        ckpt = Checkpoint(tmp_path / ".state")
        ckpt.done("tf_init")  # no image stored
        # Querying with image but none stored — returns True (backward compat)
        assert ckpt.is_done("tf_init", image="ami-whatever")

    def test_image_change_clears_stale(self, tmp_path):
        """Checkpoint with different image should be detected as stale."""
        ckpt = Checkpoint(tmp_path / ".state")
        ckpt.done("phase1_cp", image="ami-v1")
        assert ckpt.is_done("phase1_cp", image="ami-v1")
        assert not ckpt.is_done("phase1_cp", image="ami-v2")
        # Clear and redo
        ckpt.clear("phase1_cp")
        ckpt.done("phase1_cp", image="ami-v2")
        assert ckpt.is_done("phase1_cp", image="ami-v2")
