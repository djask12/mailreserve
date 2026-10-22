#!/usr/bin/env bash
# Start one bounded-registration, ephemeral runner container.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <label> <cpu-limit>" >&2
  exit 2
fi

LABEL="$1"
CPU_LIMIT="$2"
REPO="${REPO:-djask12/mailreserve}"
IMAGE="${IMAGE:-mailreserve-runner:2.338.0}"
MEMORY_LIMIT="${MEMORY_LIMIT:-6g}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND_TIMEOUT_SECONDS="${COMMAND_TIMEOUT_SECONDS:-30}"
TIMEOUT="$DIR/run_with_timeout.py"

bounded() {
  python3 "$TIMEOUT" "$1" "${@:2}"
}

if ! bounded "$COMMAND_TIMEOUT_SECONDS" docker image inspect "$IMAGE" >/dev/null; then
  echo "error: image $IMAGE is unavailable. Build it first:" >&2
  echo "  docker build -t $IMAGE scripts/self-hosted-runner" >&2
  exit 1
fi

TOKEN="$(bounded "$COMMAND_TIMEOUT_SECONDS" gh api -X POST \
  "repos/${REPO}/actions/runners/registration-token" --jq .token)"
if [ -z "$TOKEN" ]; then
  echo "error: GitHub returned an empty runner registration token" >&2
  exit 1
fi

# Swift builds are memory-hungry; the limit keeps one runaway job from starving the host.
exec docker run --rm \
  --cpus "$CPU_LIMIT" \
  --memory "$MEMORY_LIMIT" \
  -e RUNNER_REPO_URL="https://github.com/${REPO}" \
  -e RUNNER_TOKEN="$TOKEN" \
  -e RUNNER_LABELS="$LABEL" \
  -e RUNNER_NAME="${RUNNER_NAME:-$LABEL-$(date +%s)-$$}" \
  "$IMAGE"
