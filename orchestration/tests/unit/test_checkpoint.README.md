# test_checkpoint.py

Tests for `Checkpoint` class in `common.py` — file-based persistence, image tracking, and clear operations.

## Metrics

| Metric | Value |
|--------|-------|
| Total tests | 14 |
| Passed | 14 |
| Failed | 0 |
| Last run | 2026-03-30 |

> Run: `cd lb-installer && python -m pytest orchestration/tests/unit/test_checkpoint.py -v`

## Test Classes

### Basic Operations (`TestCheckpointBasic`)

| Test | Expected Behavior |
|------|-------------------|
| `test_done_creates_file` | `done("stage")` creates a file in the checkpoint dir |
| `test_is_done_false_when_missing` | `is_done("stage")` returns False before `done()` |
| `test_is_done_true_after_done` | `is_done("stage")` returns True after `done()` |
| `test_list_done` | `list_done()` returns all completed stages |
| `test_clear_single` | `clear("stage")` removes only that stage |
| `test_clear_all` | `clear_all()` removes all completed stages |
| `test_clear_nonexistent_no_error` | `clear("missing")` does not raise |
| `test_done_file_contains_timestamp` | Checkpoint file contains a timestamp |

### Image Tracking (`TestCheckpointImageTracking`)

| Test | Expected Behavior |
|------|-------------------|
| `test_done_with_image` | `done("stage", image="ami-123")` stores image metadata |
| `test_is_done_same_image` | Same image returns True |
| `test_is_done_different_image_returns_false` | Different image returns False (stale checkpoint) |
| `test_is_done_no_image_check_always_true` | No image param always returns True |
| `test_is_done_no_stored_image_any_image_true` | No stored image, any image check returns True |
| `test_image_change_clears_stale` | Image change triggers stale checkpoint clear |
