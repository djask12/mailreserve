#!/usr/bin/env bash
# Start one ephemeral 4-CPU runner for the engine and gate jobs.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$DIR/start-runner.sh" mailreserve-ci 4
