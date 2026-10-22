#!/usr/bin/env python3
"""Run one command with a portable, process-group-aware timeout."""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
from collections.abc import Sequence
from typing import Any


TIMEOUT_EXIT_CODE = 124
TERMINATE_GRACE_SECONDS = 5.0


def _terminate_process_group(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=TERMINATE_GRACE_SECONDS)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    process.wait()


def run_with_timeout(command: Sequence[str], timeout_seconds: float) -> int:
    if timeout_seconds <= 0:
        raise ValueError("timeout must be greater than zero")
    if not command:
        raise ValueError("a command is required")

    try:
        process = subprocess.Popen(command, start_new_session=True)
    except OSError as exc:
        print(f"could not start {command[0]!r}: {exc}", file=sys.stderr)
        return 127

    previous_handlers: dict[signal.Signals, Any] = {}

    def forward_signal(signum: int, _frame: object) -> None:
        _terminate_process_group(process)
        raise SystemExit(128 + signum)

    for handled_signal in (signal.SIGTERM, signal.SIGINT):
        previous_handlers[handled_signal] = signal.getsignal(handled_signal)
        signal.signal(handled_signal, forward_signal)
    try:
        try:
            return process.wait(timeout=timeout_seconds)
        except subprocess.TimeoutExpired:
            print(
                f"command timed out after {timeout_seconds:g}s: {command[0]}",
                file=sys.stderr,
            )
            _terminate_process_group(process)
            return TIMEOUT_EXIT_CODE
    finally:
        for handled_signal, previous_handler in previous_handlers.items():
            signal.signal(handled_signal, previous_handler)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("timeout_seconds", type=float)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    command = list(args.command)
    if command[:1] == ["--"]:
        command = command[1:]
    try:
        return run_with_timeout(command, args.timeout_seconds)
    except ValueError as exc:
        print(f"timeout wrapper error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
