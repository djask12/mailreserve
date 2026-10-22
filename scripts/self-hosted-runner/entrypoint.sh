#!/usr/bin/env bash
# Register, run one job, exit. `--ephemeral` is the point: every job starts from a clean
# container, so nothing (workspace, build cache, GreenMail state, processes) leaks between jobs.
set -euo pipefail

: "${RUNNER_TOKEN:?RUNNER_TOKEN is required (gh api -X POST repos/OWNER/REPO/actions/runners/registration-token)}"
: "${RUNNER_REPO_URL:?RUNNER_REPO_URL is required}"

python3 /home/runner/run_with_timeout.py 30 ./config.sh \
  --url "$RUNNER_REPO_URL" \
  --token "$RUNNER_TOKEN" \
  --name "${RUNNER_NAME:-mailreserve-ci-$(hostname)}" \
  --labels "${RUNNER_LABELS:-mailreserve-ci}" \
  --work _work \
  --ephemeral \
  --unattended \
  --replace

# The active runner is deliberately unbounded; workflow/job timeouts own it.
exec ./run.sh
