#!/usr/bin/env python3
"""Test runner for orchestration tests.

Usage:
    python orchestration/tests/run_all_tests.py              # run all
    python orchestration/tests/run_all_tests.py --unit        # unit only
    python orchestration/tests/run_all_tests.py --e2e-light   # e2e-light only
    python orchestration/tests/run_all_tests.py --verbose     # verbose output
"""

import argparse
import sys
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
UNIT_DIR = TESTS_DIR / "unit"
E2E_LIGHT_DIR = TESTS_DIR / "e2e-light"


def main():
    parser = argparse.ArgumentParser(description="Run orchestration tests")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--unit", action="store_true", help="Run unit tests only")
    group.add_argument("--e2e-light", action="store_true", help="Run e2e-light tests only")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")
    parser.add_argument("pytest_args", nargs="*", help="Additional args passed to pytest")
    args = parser.parse_args()

    try:
        import pytest
    except ImportError:
        print("pytest is required: pip install pytest", file=sys.stderr)
        sys.exit(1)

    pytest_args = []

    if args.unit:
        pytest_args.append(str(UNIT_DIR))
    elif args.e2e_light:
        pytest_args.append(str(E2E_LIGHT_DIR))
    else:
        pytest_args.append(str(TESTS_DIR))

    if args.verbose:
        pytest_args.append("-v")

    pytest_args.extend(args.pytest_args)

    sys.exit(pytest.main(pytest_args))


if __name__ == "__main__":
    main()
