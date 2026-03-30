# test_tfvars.py

Tests for `tfvars.py` — `TfVarsLoader.read_tfvars_value()` and `TfVarsLoader.update_tfvars_value()`.

## Metrics

| Metric | Value |
|--------|-------|
| Total tests | 8 |
| Passed | 8 |
| Failed | 0 |
| Last run | 2026-03-30 |

> Run: `cd lb-installer && python -m pytest orchestration/tests/unit/test_tfvars.py -v`

## Test Classes

### Read Tfvars Value (`TestReadTfvarsValue`)

| Test | Expected Behavior |
|------|-------------------|
| `test_read_string` | Reads a quoted string value from tfvars |
| `test_read_number` | Reads a numeric value from tfvars |
| `test_missing_key` | Returns "" for a key not in tfvars |
| `test_missing_file` | Returns "" when tfvars file doesn't exist |
| `test_comments_ignored` | Commented-out lines are skipped |

### Update Tfvars Value (`TestUpdateTfvarsValue`)

| Test | Expected Behavior |
|------|-------------------|
| `test_update_existing` | Updates an existing key without affecting others |
| `test_add_new` | Appends a new key=value when key doesn't exist |
| `test_quoted_value` | Handles quoted replacement values correctly |
