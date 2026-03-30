# test_deployment_mgr.py

Tests for `deployment_mgr.py` — deployment type helpers, edge cloud parsing, `KubeadmDeployment` class, discovery, and output display.

## Metrics

| Metric | Value |
|--------|-------|
| Total tests | 33 |
| Passed | 33 |
| Failed | 0 |
| Last run | 2026-03-30 |

> Run: `cd lb-installer && python -m pytest orchestration/tests/unit/test_deployment_mgr.py -v`

## Test Classes

### Deployment Type Helpers (`TestDeploymentType`)

| Test | Expected Behavior |
|------|-------------------|
| `test_ctrl` | `deployment_type("aws", "ctrl")` returns `aws-ctrl` |
| `test_edge_no_region` | `deployment_type("aws", "edge")` returns `aws-edge` |
| `test_edge_with_region` | `deployment_type("aws", "edge", "us-east-1")` returns `aws-edge-us-east-1` |
| `test_edge_helper` | `edge_deployment_type("gcp", "us-east1")` returns `gcp-edge-us-east1` |
| `test_edge_helper_no_region` | `edge_deployment_type("aws", "")` returns `aws-edge` |

### Edge Cloud From Deployment Type (`TestEdgeCloudFromDeploymentType`)

| Test | Expected Behavior |
|------|-------------------|
| `test_legacy` | `aws-edge` extracts cloud=aws, region="" |
| `test_regional` | `aws-edge-us-east-1` extracts cloud=aws, region=us-east-1 |
| `test_gcp` | `gcp-edge-us-east1` extracts cloud=gcp, region=us-east1 |
| `test_ctrl_returns_empty` | `aws-ctrl` returns ("", "") — not an edge type |

### Edge Cloud Spec Parsing (`TestParseEdgeCloudSpec`)

| Test | Expected Behavior |
|------|-------------------|
| `test_cloud_only` | `"aws"` parses to cloud=aws, region="" |
| `test_cloud_with_region` | `"aws:us-east-1"` parses to cloud=aws, region=us-east-1 |
| `test_gcp_with_zone` | `"gcp:us-east1"` parses to cloud=gcp, region=us-east1 |
| `test_invalid_cloud` | `"azure:eastus"` raises SystemExit |

### KubeadmDeployment (`TestKubeadmDeployment`)

| Test | Expected Behavior |
|------|-------------------|
| `test_init` | Sets `dt` and `customer` attributes |
| `test_status_fresh` | New deployment reports "fresh" status |
| `test_status_after_checkpoint` | All phases complete shows "all phases complete" |
| `test_discover_edge` | Discovers edge deployments for a customer |
| `test_discover_all` | Discovers both ctrl and edge deployments |
| `test_discover_all_nonexistent` | Returns empty list for nonexistent customer |

### Show Deployments (`TestShowDeployments`)

| Test | Expected Behavior |
|------|-------------------|
| `test_shows_all` | `show_deployments("hstest")` prints customer name |
| `test_show_all` | `show_deployments()` (no filter) prints customer name |
| `test_show_filtered` | `show_deployments("hstest")` prints matching customer |
| `test_shows_none` | Nonexistent customer shows nothing, no crash |

### Discover Edge Deployments (`TestDiscoverEdgeDeployments`)

| Test | Expected Behavior |
|------|-------------------|
| `test_finds_all` | Discovers legacy, regional AWS, and GCP edge dirs |
| `test_no_customer` | Returns empty list for nonexistent customer |
| `test_empty_root` | Returns empty list when deployment root has no dirs |

### Detect Ctrl Cloud (`TestDetectCtrlCloud`)

| Test | Expected Behavior |
|------|-------------------|
| `test_single_ctrl` | Returns cloud when exactly one ctrl deployment exists |
| `test_no_ctrl` | Raises SystemExit when no ctrl deployment found |
| `test_multiple_ctrl` | Raises SystemExit when multiple ctrl deployments exist |

### Show Output (`TestShowOutput`)

| Test | Expected Behavior |
|------|-------------------|
| `test_show_output_missing_tfvars` | Non-existent deployment logs warning, no crash |
| `test_show_output_existing` | Existing deployment runs `terraform output` |
| `test_show_output_with_region` | Regional edge uses correct deployment type |
| `test_show_all_outputs` | Iterates all deployments calling `show_output` |
