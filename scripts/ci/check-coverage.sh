#!/usr/bin/env bash
# Fail if line coverage of Sources/MailReserveKit is below the threshold (default 80%).
# Run after `swift test --enable-code-coverage`. Works on macOS and Linux; needs jq.
set -euo pipefail

THRESHOLD="${1:-80}"
JSON="$(swift test --show-codecov-path)"
if [ ! -f "$JSON" ]; then
  echo "error: no coverage data at $JSON; run 'swift test --enable-code-coverage' first" >&2
  exit 1
fi

read -r covered total < <(jq -r '
  [.data[0].files[] | select(.filename | test("/Sources/MailReserveKit/"))]
  | "\(map(.summary.lines.covered) | add // 0) \(map(.summary.lines.count) | add // 0)"
' "$JSON")

if [ "$total" -eq 0 ]; then
  echo "error: no MailReserveKit lines found in coverage data" >&2
  exit 1
fi

percent="$(awk -v c="$covered" -v t="$total" 'BEGIN { printf "%.1f", 100 * c / t }')"
echo "MailReserveKit line coverage: $percent% ($covered/$total lines), threshold $THRESHOLD%"
if awk -v p="$percent" -v t="$THRESHOLD" 'BEGIN { exit !(p < t) }'; then
  echo "error: coverage is below $THRESHOLD%" >&2
  exit 1
fi
