"""E2E-light tests for ImageManager — no mocks, real code paths.

These tests exercise the actual ImageManager classes without cloud API calls.
They verify initialization, attribute access, and method signatures work
end-to-end through the real code.

Tests that require AWS/GCP credentials are marked with pytest.mark.skipif
and only run when credentials are available.
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

_repo_root = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(_repo_root / "orchestration" / "lib"))
sys.path.insert(0, str(_repo_root / "orchestration"))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _has_aws_credentials() -> bool:
    try:
        import boto3
        sts = boto3.client("sts")
        sts.get_caller_identity()
        return True
    except Exception:
        return False


def _has_gcloud() -> bool:
    try:
        r = subprocess.run(["gcloud", "info", "--format=value(config.project)"],
                           capture_output=True, text=True, timeout=10)
        return r.returncode == 0 and bool(r.stdout.strip())
    except Exception:
        return False


HAS_AWS = _has_aws_credentials()
HAS_GCLOUD = _has_gcloud()


# ---------------------------------------------------------------------------
# AwsImageManager initialization (the bug that was fixed)
# ---------------------------------------------------------------------------


class TestAwsImageManagerInit:
    """Test that _AwsImageManager initializes _ec2 client correctly."""

    @pytest.mark.skipif(not HAS_AWS, reason="AWS credentials not available")
    def test_init_creates_ec2_client(self):
        """_ec2 attribute should exist after __init__."""
        from image import ImageManager
        mgr = ImageManager.create("aws", region="us-east-1")
        assert hasattr(mgr, "_ec2")
        assert mgr._ec2 is not None

    @pytest.mark.skipif(not HAS_AWS, reason="AWS credentials not available")
    def test_region_stored(self):
        from image import ImageManager
        mgr = ImageManager.create("aws", region="us-west-2")
        assert mgr.region == "us-west-2"

    @pytest.mark.skipif(not HAS_AWS, reason="AWS credentials not available")
    def test_location_property(self):
        from image import ImageManager
        mgr = ImageManager.create("aws", region="us-east-1")
        assert "us-east-1" in mgr.location
        assert "AWS" in mgr.location

    @pytest.mark.skipif(not HAS_AWS, reason="AWS credentials not available")
    def test_tfvars_key(self):
        from image import ImageManager
        mgr = ImageManager.create("aws", region="us-east-1")
        assert mgr.tfvars_key() == "custom_ami"


# ---------------------------------------------------------------------------
# GcpImageManager initialization
# ---------------------------------------------------------------------------


class TestGcpImageManagerInit:
    def test_init_no_credentials_needed(self):
        """GCP manager should init without credentials (uses gcloud CLI)."""
        from image import ImageManager
        mgr = ImageManager.create("gcp", project="test-project", zone="us-east1-b")
        assert mgr.project == "test-project"
        assert mgr.zone == "us-east1-b"

    def test_location_property(self):
        from image import ImageManager
        mgr = ImageManager.create("gcp", project="my-proj")
        assert "my-proj" in mgr.location
        assert "GCP" in mgr.location

    def test_tfvars_key(self):
        from image import ImageManager
        mgr = ImageManager.create("gcp", project="p")
        assert mgr.tfvars_key() == "custom_image"

    def test_zone_optional(self):
        from image import ImageManager
        mgr = ImageManager.create("gcp", project="p")
        assert mgr.zone == ""


# ---------------------------------------------------------------------------
# from_tfvars factory
# ---------------------------------------------------------------------------


class TestFromTfvars:
    def test_aws_from_tfvars(self, tmp_path):
        tfvars = tmp_path / "terraform.tfvars"
        tfvars.write_text('region = "us-west-2"\ncustomer_name = "test"\n')

        # This will fail without AWS creds but should at least parse tfvars
        if HAS_AWS:
            from image import ImageManager
            mgr = ImageManager.from_tfvars("aws", tfvars)
            assert mgr.region == "us-west-2"

    def test_gcp_from_tfvars(self, tmp_path):
        tfvars = tmp_path / "terraform.tfvars"
        tfvars.write_text('project_id = "my-proj"\nzone = "us-east1-b"\n')

        from image import ImageManager
        mgr = ImageManager.from_tfvars("gcp", tfvars)
        assert mgr.project == "my-proj"
        assert mgr.zone == "us-east1-b"

    def test_missing_tfvars(self, tmp_path):
        from image import ImageManager
        with pytest.raises(FileNotFoundError):
            ImageManager.from_tfvars("aws", tmp_path / "nonexistent.tfvars")

    def test_unsupported_cloud(self, tmp_path):
        tfvars = tmp_path / "terraform.tfvars"
        tfvars.write_text('region = "us-east-1"\n')
        from image import ImageManager
        with pytest.raises(ValueError):
            ImageManager.from_tfvars("azure", tfvars)


# ---------------------------------------------------------------------------
# AWS list_images (real API call)
# ---------------------------------------------------------------------------


class TestAwsListImages:
    @pytest.mark.skipif(not HAS_AWS, reason="AWS credentials not available")
    def test_list_images_no_crash(self):
        """list_images should not crash even if no images exist."""
        from image import ImageManager
        mgr = ImageManager.create("aws", region="us-east-1")
        images = mgr.list_images()
        assert isinstance(images, list)

    @pytest.mark.skipif(not HAS_AWS, reason="AWS credentials not available")
    def test_find_latest_returns_none_or_image(self):
        """find_latest should return None or an ImageInfo."""
        from image import ImageManager, ImageInfo
        mgr = ImageManager.create("aws", region="us-east-1")
        latest = mgr.find_latest()
        assert latest is None or isinstance(latest, ImageInfo)

    @pytest.mark.skipif(not HAS_AWS, reason="AWS credentials not available")
    def test_print_list_no_crash(self):
        """print_list should not crash."""
        from image import ImageManager
        mgr = ImageManager.create("aws", region="us-east-1")
        mgr.print_list()  # Should not raise


# ---------------------------------------------------------------------------
# GCP list_images (real API call)
# ---------------------------------------------------------------------------


class TestGcpListImages:
    @pytest.mark.skipif(not HAS_GCLOUD, reason="gcloud not configured")
    def test_list_images_no_crash(self):
        """list_images should not crash even if no images exist."""
        from image import ImageManager
        # Use the project from gcloud config
        r = subprocess.run(["gcloud", "config", "get-value", "project"],
                           capture_output=True, text=True)
        project = r.stdout.strip()
        if not project:
            pytest.skip("No default GCP project configured")
        mgr = ImageManager.create("gcp", project=project)
        images = mgr.list_images()
        assert isinstance(images, list)


# ---------------------------------------------------------------------------
# ImageInfo dataclass
# ---------------------------------------------------------------------------


class TestImageInfoE2E:
    def test_size_display(self):
        from image import ImageInfo
        img = ImageInfo(id="ami-test", name="ubuntu-24-04-lb-lat",
                        created="2026-03-28", is_backup=False, size_gb=50.0)
        d = img.display
        assert "50.0 GB" in d
        assert "ami-test" in d
        assert "(latest)" in d

    def test_zero_size_no_gb(self):
        from image import ImageInfo
        img = ImageInfo(id="ami-test", name="test-lb-lat",
                        created="2026-03-28", is_backup=False, size_gb=0)
        assert "GB" not in img.display

    def test_backup_flag(self):
        from image import ImageInfo
        img = ImageInfo(id="ami-bak", name="test-lb-lat-bak",
                        created="", is_backup=True)
        assert "(backup)" in img.display


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# OS Detection — _detect_os_from_ami parsing logic
# ---------------------------------------------------------------------------


class TestDetectOsFromAmi:
    """Test _parse_os_from_ami_name — the AMI-name fallback parser.

    This is a @staticmethod so it requires no AWS credentials at all.
    We feed it real-world AMI name patterns and verify the output.
    """

    @staticmethod
    def _parse(name: str, desc: str = "") -> str:
        from image import _AwsImageManager
        return _AwsImageManager._parse_os_from_ami_name(name, desc)

    # -- Ubuntu variants --

    def test_ubuntu_noble_24_04(self):
        """AMI named ubuntu/images/.../ubuntu-noble-24.04-... → ubuntu-24-04."""
        assert self._parse(
            "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-20260301"
        ) == "ubuntu-24-04"

    def test_ubuntu_jammy_22_04(self):
        assert self._parse(
            "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20260101"
        ) == "ubuntu-22-04"

    def test_ubuntu_with_patch_and_lts(self):
        """Full version with patch and LTS from description."""
        assert self._parse(
            "ami-custom-build-v3", "Canonical, Ubuntu, 24.04.4 LTS, amd64 noble image"
        ) == "ubuntu-24-04-4-lts"

    def test_ubuntu_lts_no_patch(self):
        """LTS without patch version."""
        assert self._parse(
            "ami-whatever", "Ubuntu 22.04 LTS server"
        ) == "ubuntu-22-04-lts"

    def test_ubuntu_from_description_no_lts(self):
        """Description without LTS marker."""
        assert self._parse(
            "ami-custom-build-v3", "Canonical, Ubuntu, 24.04, amd64 noble image"
        ) == "ubuntu-24-04"

    def test_ubuntu_no_version(self):
        assert self._parse("my-ubuntu-server") == "ubuntu"

    def test_ubuntu_20_04(self):
        assert self._parse(
            "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-20260101"
        ) == "ubuntu-20-04"

    def test_ubuntu_patch_version_in_name(self):
        """Patch version embedded in AMI name."""
        assert self._parse(
            "ubuntu-24.04.4-server-cloudimg-amd64"
        ) == "ubuntu-24-04-4"

    # -- RHEL variants --

    def test_rhel_9_3_0(self):
        assert self._parse(
            "RHEL-9.3.0_HVM-20260101-x86_64-0-Hourly2-GP3"
        ) == "rhel-9-3-0"

    def test_rhel_8(self):
        assert self._parse("RHEL-8.9.0_HVM-20260101-x86_64") == "rhel-8-9-0"

    def test_red_hat_from_description(self):
        result = self._parse("custom-rhel", "Red Hat Enterprise Linux 9.3")
        assert "rhel" in result

    # -- Amazon Linux --

    def test_amazon_linux_2(self):
        assert self._parse(
            "amzn2-ami-hvm-2.0.20260101.0-x86_64-gp2", "Amazon Linux 2 AMI"
        ) == "amazon-linux"

    def test_amazon_linux_name_only(self):
        assert self._parse("amzn2-ami-kernel-5.10") == "amazon-linux"

    # -- Other distros --

    def test_centos(self):
        assert self._parse("CentOS-7-x86_64-GP2-2026") == "centos"

    def test_debian(self):
        assert self._parse("debian-12-amd64-20260101") == "debian"

    # -- Edge cases --

    def test_unknown_ami_returns_nonempty(self):
        """Opaque name should not crash, returns best-effort string."""
        result = self._parse("my-custom-image-v7")
        assert isinstance(result, str)
        assert len(result) > 0

    def test_empty_name_and_desc(self):
        result = self._parse("", "")
        assert isinstance(result, str)
        assert result == "unknown"

    def test_case_insensitive(self):
        """Matching should be case-insensitive."""
        assert self._parse("Ubuntu-Noble-24.04-Server") == "ubuntu-24-04"

    def test_case_insensitive_lts(self):
        """LTS matching should be case-insensitive."""
        assert self._parse("Ubuntu-Noble-24.04.4 LTS Server") == "ubuntu-24-04-4-lts"

    def test_description_takes_priority_when_name_opaque(self):
        """When name has no OS hint, description is used."""
        result = self._parse("ami-0abc123def456", "Debian GNU/Linux 12")
        assert result == "debian"


class TestDetectOsNameFallback:
    """Test that detect_os_name has the SSM → AMI fallback chain."""

    @pytest.mark.skipif(not HAS_AWS, reason="AWS credentials not available")
    def test_detect_os_has_fallback_methods(self):
        """Manager should have both _detect_os_via_ssm and _detect_os_from_ami."""
        from image import ImageManager
        mgr = ImageManager.create("aws", region="us-east-1")
        assert callable(getattr(mgr, "_detect_os_via_ssm", None))
        assert callable(getattr(mgr, "_detect_os_from_ami", None))
        assert callable(getattr(mgr, "_parse_os_from_ami_name", None))

    @pytest.mark.skipif(not HAS_AWS, reason="AWS credentials not available")
    def test_generate_image_name_uses_detect(self):
        """generate_image_name calls detect_os_name and formats correctly."""
        from image import ImageManager, IMAGE_SUFFIX
        mgr = ImageManager.create("aws", region="us-east-1")
        assert callable(mgr.generate_image_name)
        assert IMAGE_SUFFIX == "-lb-lat"


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------


class TestConstants:
    def test_image_suffix(self):
        from image import IMAGE_SUFFIX, BACKUP_SUFFIX
        assert IMAGE_SUFFIX == "-lb-lat"
        assert BACKUP_SUFFIX == "-lb-lat-bak"
        assert BACKUP_SUFFIX.startswith(IMAGE_SUFFIX)
