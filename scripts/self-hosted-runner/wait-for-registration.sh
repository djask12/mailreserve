#!/usr/bin/env bash
# Confirm one exact runner registration. The supervisor applies the outer bound.
set -uo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <runner-name> <label>" >&2
  exit 2
fi

RUNNER_NAME="$1"
LABEL="$2"
REPO="${REPO:-djask12/mailreserve}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_TIMEOUT_SECONDS="${REGISTRATION_API_TIMEOUT_SECONDS:-5}"
POLL_SECONDS="${REGISTRATION_POLL_SECONDS:-1}"

while true; do
  raw="$(python3 "$DIR/run_with_timeout.py" "$API_TIMEOUT_SECONDS" gh api \
    --paginate --slurp "repos/$REPO/actions/runners?per_page=100")"
  status=$?
  if [ "$status" -eq 0 ]; then
    normalized="$(printf '%s' "$raw" | python3 "$DIR/runner_inventory.py" normalize)"
    status=$?
    if [ "$status" -eq 0 ]; then
      found="$(printf '%s' "$normalized" | python3 "$DIR/runner_inventory.py" \
        runner-online --name "$RUNNER_NAME" --label "$LABEL")"
      if [ "$?" -eq 0 ] && [ "$found" = "true" ]; then
        exit 0
      fi
    fi
  fi
  sleep "$POLL_SECONDS"
done
