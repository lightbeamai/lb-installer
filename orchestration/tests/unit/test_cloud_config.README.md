# test_cloud_config.py

Tests for `cloud_config.py` — `CtrlCloudConfig` and `EdgeCloudConfig` dataclasses with cloud-specific defaults.

## Metrics

| Metric | Value |
|--------|-------|
| Total tests | 11 |
| Passed | 11 |
| Failed | 0 |
| Last run | 2026-03-30 |

> Run: `cd lb-installer && python -m pytest orchestration/tests/unit/test_cloud_config.py -v`

## Test Classes

### Ctrl Config (`TestCtrlConfig`)

| Test | Expected Behavior |
|------|-------------------|
| `test_aws_ctrl_defaults` | AWS ctrl has t3.small CP, m6i.2xlarge workers, 500 GB data disk |
| `test_gcp_ctrl_defaults` | GCP ctrl has e2-standard-8 for both CP and workers, no gateway |
| `test_unknown_cloud_raises` | `get_ctrl_config("azure")` raises ValueError |
| `test_read_from_tfvars` | Reads actual values from tfvars file |
| `test_read_uses_default` | Falls back to defaults when key missing from tfvars |
| `test_disk_summary_aws` | AWS disk summary shows root + EBS sizes |
| `test_disk_summary_gcp` | GCP disk summary shows boot + data sizes |

### Edge Config (`TestEdgeConfig`)

| Test | Expected Behavior |
|------|-------------------|
| `test_aws_edge_defaults` | AWS edge has m6i.4xlarge type, 100 GB disk |
| `test_gcp_edge_defaults` | GCP edge has e2-standard-16 type |
| `test_unknown_cloud_raises` | `get_edge_config("azure")` raises ValueError |
| `test_read_from_tfvars` | Reads instance_count and instance_type from tfvars |
