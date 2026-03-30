# Orchestration Tests

## Directory Structure

```
tests/
  unit/              # Fast, isolated tests — no cloud credentials needed
  e2e-light/         # Real code paths, no mocks — some tests need credentials
  run_all_tests.py   # CLI runner for unit, e2e-light, or all
```

## Requirements

**Python:** 3.9+

**Install dependencies:**

```bash
pip install pytest boto3
```

| Package | Required for | Notes |
|---------|-------------|-------|
| `pytest` | All tests | Test framework |
| `boto3` | AWS-related tests | Unit tests mock it; e2e-light tests that need it skip if unavailable |

**Optional (for full e2e-light coverage):**

| Credential | Tests unlocked |
|------------|---------------|
| AWS credentials (`aws configure` or `AWS_PROFILE`) | AWS ImageManager init, list, detect OS |
| GCP (`gcloud auth login` + default project) | GCP image listing |

Without credentials, all credential-dependent tests skip automatically — nothing fails.

## Quick Start

```bash
cd lb-installer

# Run all tests
python orchestration/tests/run_all_tests.py

# Run only unit tests
python orchestration/tests/run_all_tests.py --unit

# Run only e2e-light tests
python orchestration/tests/run_all_tests.py --e2e-light

# Run with verbose output
python orchestration/tests/run_all_tests.py --verbose

# Or use pytest directly
python -m pytest orchestration/tests/ -v
python -m pytest orchestration/tests/unit/ -v
python -m pytest orchestration/tests/e2e-light/ -v
```

## Test Categories

### Unit Tests (`tests/unit/`)

- Fast, deterministic, no external dependencies
- Use mocks/patches for cloud APIs, filesystem, and subprocess calls
- Every test runs without AWS/GCP credentials
- Target: orchestrator CLI logic, argument parsing, control flow

### E2E-Light Tests (`tests/e2e-light/`)

- Exercise real code paths with no mocks
- Tests needing cloud credentials are auto-skipped via `pytest.mark.skipif`
- Safe to run anywhere — credential-dependent tests skip gracefully
- Target: class initialization, data parsing, image name generation

## Guidelines

1. **No credentials required by default.** All tests must pass (or skip) without AWS/GCP credentials configured. Use `pytest.mark.skipif` for tests that need credentials.

2. **No cloud side effects.** Tests must never create, modify, or delete cloud resources unless explicitly gated behind credentials AND clearly documented.

3. **Imports inside test functions.** Import the module under test inside each test method, not at module level. This prevents import failures from blocking unrelated tests.

4. **One concern per test.** Each test should verify one behavior. Name it `test_<what>_<expected>` (e.g. `test_ubuntu_noble_24_04`, `test_missing_tfvars`).

5. **Keep tests fast.** Unit tests should complete in under 1 second total. E2e-light tests without credentials should complete in under 10 seconds.

6. **Pair with a README.** Each test file should have a companion `<test_file>.README.md` documenting the test matrix and last-run metrics.
