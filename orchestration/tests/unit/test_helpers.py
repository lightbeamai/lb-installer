"""Tests for installer.helpers — prompt, Spinner, setup_logging."""

import sys
import threading
import time
from pathlib import Path
from unittest import mock

import pytest

_repo_root = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(_repo_root / "orchestration" / "lib"))

from helpers import prompt, setup_logging, Spinner


class TestPrompt:
    def test_prompt_returns_input(self):
        with mock.patch("builtins.input", return_value="yes"):
            assert prompt("Continue? ") == "yes"

    def test_prompt_calls_stty_sane(self):
        with mock.patch("builtins.input", return_value=""), \
             mock.patch("subprocess.run") as mock_run:
            prompt("test: ")
            # stty sane should be called
            mock_run.assert_called_once()
            assert "stty" in str(mock_run.call_args)


class TestSpinner:
    def test_spinner_context_manager(self):
        with Spinner("testing...") as sp:
            assert sp is not None
            time.sleep(0.2)

    def test_spinner_update(self):
        with Spinner("start") as sp:
            sp.update("updated")
            assert sp._message == "updated"

    def test_spinner_stops_on_exit(self):
        sp = Spinner("test")
        sp.__enter__()
        assert sp._thread is not None
        assert sp._thread.is_alive()
        sp.__exit__(None, None, None)
        assert not sp._thread.is_alive()


class TestSetupLogging:
    def test_setup_logging_no_error(self):
        setup_logging()  # should not raise
