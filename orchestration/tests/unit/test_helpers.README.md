# test_helpers.py

Tests for `helpers.py` — `prompt()`, `Spinner`, and `setup_logging()`.

## Metrics

| Metric | Value |
|--------|-------|
| Total tests | 6 |
| Passed | 6 |
| Failed | 0 |
| Last run | 2026-03-30 |

> Run: `cd lb-installer && python -m pytest orchestration/tests/unit/test_helpers.py -v`

## Test Classes

### Prompt (`TestPrompt`)

| Test | Expected Behavior |
|------|-------------------|
| `test_prompt_returns_input` | Returns user input string |
| `test_prompt_calls_stty_sane` | Calls `stty sane` to restore terminal settings |

### Spinner (`TestSpinner`)

| Test | Expected Behavior |
|------|-------------------|
| `test_spinner_context_manager` | Works as context manager without error |
| `test_spinner_update` | `update()` changes the displayed message |
| `test_spinner_stops_on_exit` | Thread stops when exiting context |

### Setup Logging (`TestSetupLogging`)

| Test | Expected Behavior |
|------|-------------------|
| `test_setup_logging_no_error` | Configures logging without raising |
