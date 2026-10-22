#!/usr/bin/env python3
"""Validate and query a complete GitHub Actions runner inventory."""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Sequence
from typing import Any


class InventoryError(ValueError):
    """The inventory is absent, partial, or malformed."""


def _load() -> dict[str, Any]:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        raise InventoryError(f"malformed JSON: {exc}") from exc

    pages = payload if isinstance(payload, list) else [payload]
    if not pages or any(not isinstance(page, dict) for page in pages):
        raise InventoryError("inventory must contain at least one response object")

    totals = [page.get("total_count") for page in pages]
    if any(type(total) is not int or total < 0 for total in totals):
        raise InventoryError("every page must contain a non-negative total_count")
    if len(set(totals)) != 1:
        raise InventoryError("paginated inventory total_count values disagree")

    runners: list[dict[str, Any]] = []
    for page in pages:
        page_runners = page.get("runners")
        if not isinstance(page_runners, list):
            raise InventoryError("every page must contain a runners list")
        runners.extend(page_runners)
    if totals[0] != len(runners):
        raise InventoryError(
            f"inventory is incomplete: total_count={totals[0]}, received={len(runners)}"
        )

    seen_ids: set[int] = set()
    normalized: list[dict[str, Any]] = []
    for runner in runners:
        if not isinstance(runner, dict):
            raise InventoryError("runner entries must be objects")
        runner_id = runner.get("id")
        name = runner.get("name")
        status = runner.get("status")
        busy = runner.get("busy")
        labels = runner.get("labels")
        if type(runner_id) is not int or runner_id <= 0 or runner_id in seen_ids:
            raise InventoryError("runner IDs must be unique positive integers")
        if not isinstance(name, str) or not name:
            raise InventoryError("runner names must be non-empty strings")
        if status not in {"online", "offline"}:
            raise InventoryError("runner status must be online or offline")
        if type(busy) is not bool:
            raise InventoryError("runner busy must be a boolean")
        if not isinstance(labels, list):
            raise InventoryError("runner labels must be a list")
        label_names: list[str] = []
        for label in labels:
            # `normalize` emits strings, while the GitHub API emits objects.
            # Query operations deliberately accept both so one validated
            # inventory can be normalized once and queried throughout a cycle.
            label_name = label if isinstance(label, str) else None
            if isinstance(label, dict):
                label_name = label.get("name")
            if not isinstance(label_name, str) or not label_name:
                raise InventoryError("runner label names must be non-empty strings")
            label_names.append(label_name)
        seen_ids.add(runner_id)
        normalized.append(
            {
                "id": runner_id,
                "name": name,
                "status": status,
                "busy": busy,
                "labels": label_names,
            }
        )
    return {"total_count": totals[0], "runners": normalized}


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="action", required=True)
    subparsers.add_parser("normalize")

    online = subparsers.add_parser("online-count")
    online.add_argument("--label", required=True)

    offline = subparsers.add_parser("offline-ids")
    offline.add_argument("--owned-prefix", required=True)

    registered = subparsers.add_parser("runner-online")
    registered.add_argument("--name", required=True)
    registered.add_argument("--label", required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        inventory = _load()
    except InventoryError as exc:
        print(f"invalid runner inventory: {exc}", file=sys.stderr)
        return 1

    runners = inventory["runners"]
    if args.action == "normalize":
        print(json.dumps(inventory, separators=(",", ":"), sort_keys=True))
    elif args.action == "online-count":
        print(
            sum(
                runner["status"] == "online" and args.label in runner["labels"]
                for runner in runners
            )
        )
    elif args.action == "offline-ids":
        for runner in runners:
            if runner["status"] == "offline" and runner["name"].startswith(
                args.owned_prefix
            ):
                print(runner["id"])
    elif args.action == "runner-online":
        matches = [
            runner
            for runner in runners
            if runner["name"] == args.name
            and runner["status"] == "online"
            and args.label in runner["labels"]
        ]
        print("true" if len(matches) == 1 else "false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
