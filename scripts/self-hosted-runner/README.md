# Self-hosted CI runners

Ephemeral GitHub Actions runners for MailReserve's Linux CI jobs (`engine (Linux)` and `CI gate`),
running in Docker on the owner's Mac. Adapted from `djask12/certifyrapp`.

- **Ephemeral:** each container registers, runs exactly one job, and exits. The supervisor keeps
  `CI_RUNNERS` (default 2) idle runners online with the label `mailreserve-ci`.
- **Fork PRs never run here.** `.github/workflows/ci.yml` routes fork PRs to `ubuntu-latest`. The
  repo also requires approval before workflows run for outside contributors.
- **No Docker socket in the runner.** GreenMail runs inside the job (`scripts/ci/start-greenmail.sh`).
- macOS jobs run on GitHub-hosted `macos-latest`, not here.

| File | Purpose |
|---|---|
| `Dockerfile` | `swift:6.4.0-noble` + Java (GreenMail) + jq + gh + pinned actions runner |
| `entrypoint.sh` | Registers one ephemeral runner, runs one job |
| `start-runner.sh` | Fetches a registration token with `gh`, starts one container (`--cpus`, `--memory`) |
| `run-runner.sh` | `start-runner.sh mailreserve-ci 4` |
| `supervise.sh` | Rebuilds the image when its sources change, prunes offline registrations it owns, keeps the fleet topped up |
| `wait-for-registration.sh`, `runner_inventory.py`, `run_with_timeout.py` | Supervisor helpers |
| `com.mailreserve.runners.plist` | launchd agent that keeps `supervise.sh` running (install steps inside) |

## Setup (once)

Requires Docker Desktop and an authenticated `gh` with admin rights on the repo.

```bash
docker build -t mailreserve-runner:2.338.0 scripts/self-hosted-runner
sed "s|__REPO_DIR__|$PWD|g" scripts/self-hosted-runner/com.mailreserve.runners.plist \
  > ~/Library/LaunchAgents/com.mailreserve.runners.plist
launchctl load ~/Library/LaunchAgents/com.mailreserve.runners.plist
gh api repos/djask12/mailreserve/actions/runners --jq '.runners[] | "\(.name) \(.status)"'
gh variable set CI_RUNNER --repo djask12/mailreserve --body mailreserve-ci
```

The launchd agent runs the scripts from this checkout, so keep the checkout in place. The
supervisor rebuilds the image automatically when `Dockerfile`, `entrypoint.sh` or
`run_with_timeout.py` change.

## Escape hatch

If the fleet is down, `gh variable delete CI_RUNNER --repo djask12/mailreserve` sends new runs to
GitHub-hosted `ubuntu-latest`. Set it again once the fleet is back.

## Resources

Docker Desktop's CPU and memory allocation is shared with any other runner fleets on this Mac.
Each MailReserve runner is capped at 4 CPUs and 6 GB (`MEMORY_LIMIT`).
