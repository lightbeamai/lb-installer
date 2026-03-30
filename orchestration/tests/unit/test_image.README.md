# test_image.py

Tests for `image.py` — `ImageInfo` dataclass, `ImageManager` factory, auto-resolve logic, and OS detection.

## Metrics

| Metric | Value |
|--------|-------|
| Total tests | 19 (6 skipped without AWS credentials) |
| Passed | 13 |
| Skipped | 6 |
| Failed | 0 |
| Last run | 2026-03-30 |

> Run: `cd lb-installer && python -m pytest orchestration/tests/unit/test_image.py -v`

## Test Classes

### ImageInfo Display (`TestImageInfo`)

| Test | Expected Behavior |
|------|-------------------|
| `test_display_latest` | Non-backup shows "(latest)", size "50.0 GB", and ID |
| `test_display_backup` | Backup image shows "(backup)" |
| `test_display_zero_size` | Size 0 omits "GB" from display |
| `test_display_pending_state` | Pending image shows "[pending]" |
| `test_display_available_no_state_label` | Available image omits "[available]" |

### Image Constants (`TestImageConstants`)

| Test | Expected Behavior |
|------|-------------------|
| `test_suffixes` | `IMAGE_SUFFIX` is `-lb-lat`, `BACKUP_SUFFIX` is `-lb-lat-bak` |

### ImageManager Factory (`TestImageManagerFactory`)

| Test | Expected Behavior |
|------|-------------------|
| `test_create_aws` | Returns manager with `tfvars_key()` = "custom_ami" (requires AWS creds) |
| `test_create_gcp` | Returns manager with `tfvars_key()` = "custom_image" |
| `test_create_unsupported` | `"azure"` raises ValueError |

### Auto Resolve Image (`TestAutoResolveImage`)

| Test | Expected Behavior |
|------|-------------------|
| `test_no_published_image_flag` | `no_published_image=True` returns None |
| `test_current_custom_in_tfvars` | Existing custom image in tfvars returned as-is |
| `test_current_matches_latest` | Current matches latest — returns current |
| `test_auto_detect_published` | Published image found — returns its ID |
| `test_no_images_returns_none` | No published image — returns None |

### OS Detection (`TestOsDetection`)

All tests require AWS credentials and are skipped without them.

| Test | Expected Behavior |
|------|-------------------|
| `test_ubuntu_24_04` | AMI name `ubuntu-noble-24.04` parses to `ubuntu-24-04` |
| `test_ubuntu_lts` | Description `Ubuntu, 24.04.4 LTS` parses to `ubuntu-24-04-4-lts` |
| `test_rhel` | AMI name `RHEL-9.3.0_HVM` parses to `rhel-9-3-0` |
| `test_amazon_linux` | AMI name `amzn2-ami-hvm` parses to `amazon-linux` |
| `test_unknown` | Empty name/desc returns `unknown` |
