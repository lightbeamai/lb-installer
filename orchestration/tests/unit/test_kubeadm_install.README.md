# test_kubeadm_install.py

Tests for CLI dispatch, action routing, edge spec normalization, reset handling, and auto-detection in `kubeadm_cli.py`.

> **Note:** Deployment discovery, tfvars, image, and checkpoint tests have been split into dedicated test files. This file retains only CLI-level integration tests. Some test classes still exist here as duplicates during migration — they will be removed once the split files are verified.

## Metrics

| Metric | Value |
|--------|-------|
| Total tests | 79 |
| Passed | 79 |
| Failed | 0 |
| Last run | 2026-03-30 |

> Run: `cd lb-installer && python -m pytest orchestration/tests/unit/test_kubeadm_install.py -v`

## Test Classes

### Action Routing (`TestActionRouting`)

| Test | Expected Behavior |
|------|-------------------|
| `test_output_no_confirmation` | `--action output` runs without prompting |
| `test_show_no_confirmation` | `--action show` calls show_output without prompting |
| `test_destroy_confirmation_required` | `--action destroy` prompts for confirmation, cancels on "n" |
| `test_terraform_only_no_confirmation` | `--action init/apply/output/cleanup-state` run without prompting |

### Edge Spec Normalization (`TestEdgeSpecNormalization`)

| Test | Expected Behavior |
|------|-------------------|
| `test_comma_separated` | `aws:us-east-1,gcp:us-east1` parses into two edge specs |
| `test_space_separated` | Space-separated args parse into two edge specs |
| `test_cloud_only_no_region` | `aws` parses as cloud=aws with empty region |

### Reset Handling (`TestResetHandling`)

| Test | Expected Behavior |
|------|-------------------|
| `test_reset_all_returns_early` | `--reset all` clears checkpoints and exits without prompting |
| `test_reset_specific_stage` | `--reset phase1_cp` clears that stage then continues to prompt |

### Auto-Detect (`TestAutoDetect`)

| Test | Expected Behavior |
|------|-------------------|
| `test_auto_detect_ctrl_and_edges` | No `--ctrl-cloud` or `--edge-cloud` auto-detects from deployment dirs |
| `test_auto_detect_no_customer_show` | No customer with `--action show` lists all deployments |
| `test_auto_detect_no_customer_install_fails` | No customer with `--action all` raises SystemExit |
| `test_ctrl_only_no_edge_autodiscovery` | `--ctrl-cloud aws` alone installs only ctrl, no edges |
| `test_edge_only_no_ctrl` | `--edge-cloud aws` alone installs only edge, no ctrl |
| `test_ctrl_and_edge_explicit` | `--ctrl-cloud aws --edge-cloud aws` installs both ctrl and edge |

### Legacy Tests (pending migration)

The following test classes are duplicated in dedicated test files and will be removed from this file:

- `TestParseEdgeCloudSpec`, `TestEdgeDeploymentType`, `TestEdgeCloudFromDeploymentType`, `TestDiscoverEdgeDeployments`, `TestDetectCtrlCloud`, `TestDiscoverAllDeployments`, `TestShowOutput`, `TestShowDeployments` → `test_deployment_mgr.py`
- `TestImageInfo`, `TestImageManagerFactory`, `TestAutoResolveImage`, `TestImageManagerOperations`, `TestImageInfoSize`, `TestDeleteMatching`, `TestAwsAmiSize`, `TestImageConstants` → `test_image.py`
- `TestReadTfvarsValue`, `TestUpdateTfvarsValue` → `test_tfvars.py`
