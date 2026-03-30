"""Tests for installer.image — ImageInfo, ImageManager, OS detection."""

import sys
from pathlib import Path
from unittest import mock

import pytest

_repo_root = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(_repo_root / "orchestration" / "lib"))
sys.path.insert(0, str(_repo_root / "orchestration"))

from image import ImageInfo, IMAGE_SUFFIX, BACKUP_SUFFIX


def _has_aws():
    try:
        import boto3
        boto3.client("sts").get_caller_identity()
        return True
    except Exception:
        return False


class TestImageInfo:
    def test_display_latest(self):
        img = ImageInfo(id="ami-1", name="test-lb-lat", created="2026-03-28",
                        is_backup=False, size_gb=50.0)
        assert "(latest)" in img.display
        assert "50.0 GB" in img.display
        assert "ami-1" in img.display

    def test_display_backup(self):
        img = ImageInfo(id="ami-2", name="test-lb-lat-bak", created="",
                        is_backup=True)
        assert "(backup)" in img.display

    def test_display_zero_size(self):
        img = ImageInfo(id="ami-3", name="test-lb-lat", created="",
                        is_backup=False, size_gb=0)
        assert "GB" not in img.display

    def test_display_pending_state(self):
        img = ImageInfo(id="ami-4", name="test-lb-lat", created="",
                        is_backup=False, state="pending")
        assert "[pending]" in img.display

    def test_display_available_no_state_label(self):
        img = ImageInfo(id="ami-5", name="test-lb-lat", created="",
                        is_backup=False, state="available")
        assert "[available]" not in img.display


class TestImageConstants:
    def test_suffixes(self):
        assert IMAGE_SUFFIX == "-lb-lat"
        assert BACKUP_SUFFIX == "-lb-lat-bak"
        assert BACKUP_SUFFIX.startswith(IMAGE_SUFFIX)


class TestImageManagerFactory:
    @pytest.mark.skipif(not _has_aws(), reason="AWS credentials not available")
    def test_create_aws(self):
        from image import ImageManager
        mgr = ImageManager.create("aws", region="us-east-1")
        assert mgr.tfvars_key() == "custom_ami"

    def test_create_gcp(self):
        from image import ImageManager
        mgr = ImageManager.create("gcp", project="test", zone="us-east1-b")
        assert mgr.tfvars_key() == "custom_image"

    def test_create_unsupported(self):
        from image import ImageManager
        with pytest.raises(ValueError):
            ImageManager.create("azure")


class TestAutoResolveImage:
    def _make_mgr(self):
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
        assert mgr.auto_resolve_image(no_published_image=True) is None

    def test_current_custom_in_tfvars(self):
        MockMgr, _ = self._make_mgr()
        mgr = MockMgr()
        result = mgr.auto_resolve_image(current_custom_image="ami-from-tfvars")
        assert result == "ami-from-tfvars"

    def test_current_matches_latest(self):
        MockMgr, ImageInfo = self._make_mgr()
        latest = ImageInfo(id="ami-same", name="test", created="", is_backup=False)
        mgr = MockMgr(latest=latest)
        assert mgr.auto_resolve_image(current_custom_image="ami-same") == "ami-same"

    def test_auto_detect_published(self):
        MockMgr, ImageInfo = self._make_mgr()
        latest = ImageInfo(id="ami-auto", name="ubuntu-lb-lat", created="", is_backup=False)
        mgr = MockMgr(latest=latest)
        assert mgr.auto_resolve_image() == "ami-auto"

    def test_no_images_returns_none(self):
        MockMgr, _ = self._make_mgr()
        mgr = MockMgr(latest=None)
        assert mgr.auto_resolve_image() is None


class TestOsDetection:
    """Test _parse_os_from_ami_name — AMI name parsing."""

    @staticmethod
    def _parse(name, desc=""):
        from image import _AwsImageManager
        return _AwsImageManager._parse_os_from_ami_name(name, desc)

    @pytest.mark.skipif(not _has_aws(), reason="AWS credentials not available")
    def test_ubuntu_24_04(self):
        assert self._parse("ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64") == "ubuntu-24-04"

    @pytest.mark.skipif(not _has_aws(), reason="AWS credentials not available")
    def test_ubuntu_lts(self):
        assert self._parse("", "Ubuntu, 24.04.4 LTS") == "ubuntu-24-04-4-lts"

    @pytest.mark.skipif(not _has_aws(), reason="AWS credentials not available")
    def test_rhel(self):
        assert self._parse("RHEL-9.3.0_HVM-20260101") == "rhel-9-3-0"

    @pytest.mark.skipif(not _has_aws(), reason="AWS credentials not available")
    def test_amazon_linux(self):
        assert self._parse("amzn2-ami-hvm") == "amazon-linux"

    @pytest.mark.skipif(not _has_aws(), reason="AWS credentials not available")
    def test_unknown(self):
        result = self._parse("", "")
        assert result == "unknown"
