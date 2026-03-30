# test_image_manager.py

E2E-light tests for `ImageManager` — no mocks, real code paths. Tests that require cloud credentials are auto-skipped when credentials are unavailable.

## Metrics

| Metric | Value |
|--------|-------|
| Total tests | 42 |
| Passed (no creds) | 33 |
| Skipped (needs AWS/GCP) | 9 |
| Failed | 0 |
| Last run | 2026-03-28 |

> Run: `cd lb-installer && python -m pytest orchestration/tests/e2e-light/test_image_manager.py -v`
>
> With AWS creds: `AWS_PROFILE=default python -m pytest orchestration/tests/e2e-light/ -v`

### AWS ImageManager Init (`TestAwsImageManagerInit`)

| Test | Expected Behavior |
|------|-------------------|
| `test_init_creates_ec2_client` | `_ec2` attribute exists after init (requires AWS creds) |
| `test_region_stored` | `mgr.region` matches the region passed to create |
| `test_location_property` | `location` returns "AWS region us-east-1" |
| `test_tfvars_key` | Returns "custom_ami" |

### GCP ImageManager Init (`TestGcpImageManagerInit`)

| Test | Expected Behavior |
|------|-------------------|
| `test_init_no_credentials_needed` | GCP manager inits without credentials |
| `test_location_property` | `location` returns "GCP project my-proj" |
| `test_tfvars_key` | Returns "custom_image" |
| `test_zone_optional` | Zone defaults to "" when not provided |

### from_tfvars Factory (`TestFromTfvars`)

| Test | Expected Behavior |
|------|-------------------|
| `test_aws_from_tfvars` | Reads region from tfvars, creates AWS manager |
| `test_gcp_from_tfvars` | Reads project_id and zone from tfvars |
| `test_missing_tfvars` | Raises FileNotFoundError for nonexistent file |
| `test_unsupported_cloud` | Raises ValueError for "azure" |

### AWS List Images (`TestAwsListImages`)

| Test | Expected Behavior |
|------|-------------------|
| `test_list_images_no_crash` | Returns a list (empty or not), no crash (requires AWS creds) |
| `test_find_latest_returns_none_or_image` | Returns None or ImageInfo (requires AWS creds) |
| `test_print_list_no_crash` | Prints without crashing (requires AWS creds) |

### GCP List Images (`TestGcpListImages`)

| Test | Expected Behavior |
|------|-------------------|
| `test_list_images_no_crash` | Returns a list, no crash (requires gcloud configured) |

### ImageInfo E2E (`TestImageInfoE2E`)

| Test | Expected Behavior |
|------|-------------------|
| `test_size_display` | 50 GB image shows "50.0 GB" and "(latest)" |
| `test_zero_size_no_gb` | 0 size omits "GB" from display |
| `test_backup_flag` | Backup image shows "(backup)" |

### OS Detection — AMI Name Parsing (`TestDetectOsFromAmi`)

| Test | Expected Behavior |
|------|-------------------|
| `test_ubuntu_noble_24_04` | `ubuntu/images/.../ubuntu-noble-24.04-...` → `ubuntu-24-04` |
| `test_ubuntu_jammy_22_04` | `ubuntu-jammy-22.04-...` → `ubuntu-22-04` |
| `test_ubuntu_from_description_only` | Opaque name + Ubuntu description → `ubuntu-24-04` |
| `test_ubuntu_no_version` | `my-ubuntu-server` → `ubuntu` |
| `test_ubuntu_20_04` | `ubuntu-focal-20.04-...` → `ubuntu-20-04` |
| `test_rhel_9_3_0` | `RHEL-9.3.0_HVM-...` → `rhel-9-3-0` |
| `test_rhel_8` | `RHEL-8.9.0_HVM-...` → `rhel-8-9-0` |
| `test_red_hat_from_description` | Description "Red Hat Enterprise Linux 9.3" → contains `rhel` |
| `test_amazon_linux_2` | `amzn2-ami-hvm-...` → `amazon-linux` |
| `test_amazon_linux_name_only` | `amzn2-ami-kernel-...` → `amazon-linux` |
| `test_centos` | `CentOS-7-...` → `centos` |
| `test_debian` | `debian-12-...` → `debian` |
| `test_unknown_ami_returns_nonempty` | Opaque name returns non-empty string |
| `test_empty_name_and_desc` | Empty inputs return `unknown` |
| `test_case_insensitive` | `Ubuntu-Noble-24.04-Server` → `ubuntu-24-04` |
| `test_description_takes_priority_when_name_opaque` | AMI ID name + Debian description → `debian` |

### OS Detection — Fallback Chain (`TestDetectOsNameFallback`)

| Test | Expected Behavior |
|------|-------------------|
| `test_detect_os_has_fallback_methods` | Manager has `_detect_os_via_ssm`, `_detect_os_from_ami`, `_parse_os_from_ami_name` (requires AWS creds) |
| `test_generate_image_name_uses_detect` | `generate_image_name` is callable, IMAGE_SUFFIX is `-lb-lat` (requires AWS creds) |

### Constants (`TestConstants`)

| Test | Expected Behavior |
|------|-------------------|
| `test_image_suffix` | IMAGE_SUFFIX is "-lb-lat", BACKUP_SUFFIX is "-lb-lat-bak" |
