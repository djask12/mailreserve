# AGENTS.md

**This file is the single source of truth for how agents and contributors work in this repository.**
Codex reads it natively; Claude Code imports it through `@AGENTS.md` in `CLAUDE.md`, so both tools
get identical rules. Put shared rules here, not in `CLAUDE.md`.

**Ask the user before editing `AGENTS.md` or `CLAUDE.md`.**

Companion files:
- [`README.md`](README.md): product overview, setup, install, contributor commands
- `plans/`: local, gitignored implementation plans (see [Plans](#plans-required))
- `notes/`: local, gitignored live task notes for handoff between agents (see [Task notes](#task-notes-required))

---

## Project overview

MailReserve is a free, open source (MIT) macOS app that backs up Gmail, Yahoo and generic IMAP
mailboxes into plain `.eml` files, one per message, with a SQLite full-text index for search.
It is not an email client: no composing or sending.

### Architecture

| Part | Path | Notes |
|---|---|---|
| Engine | `Sources/MailReserveKit/` | IMAP sync, archive writer, index, run logs. **No SwiftUI/AppKit.** Must build on Linux (CI runs it there) except for clearly separated macOS adapters such as the Keychain store (`#if canImport(Security)`). |
| CLI | `Sources/mailreserve/` | Thin wrapper over the engine: `backup`, `verify`, `reindex`. |
| App | `App/` | SwiftUI menu bar app + main window. Depends on the local package. |
| Spike | `Spike/` | Milestone 0 throwaway; deleted once its gate passes. |

Core invariants:
- The `.eml` files are the source of truth. The SQLite index can always be rebuilt from them.
- The engine never modifies or deletes an `.eml` file after it is written. Messages deleted on
  the server are kept and flagged `deleted_on_server` in the index.
- Each message is stored once (Gmail `X-GM-MSGID`, else `Message-ID`, else SHA-256 of raw bytes);
  extra folders and labels are rows in the index.
- Writes are crash-safe: `.partial` file, fsync, atomic rename, then commit the index row.
- Design for 100k+ messages per account: stream to disk, fetch and index in batches, never hold a
  mailbox in memory.

Milestones (M0 spike → M1 engine → M2 app shell → M3 search → M4 v0.1) are listed in the README
roadmap.

---

## Session start (required)

Before starting anything new, check whether a previous session (Claude or Codex) left work in flight:

```bash
grep -l '^\*\*Status:\*\* \(In progress\|Blocked\)' notes/*.md
```

Read every match in full, then verify it against reality before resuming:
`git status`, `git log --oneline -10`, the branch named in the note, and any PR or CI run it cites.
Resume from its **Next step**. If an active note is unrelated to the user's current request,
mention it and follow the current request.

## Plans (required)

Non-trivial work (3+ steps, or any architectural decision) gets a written plan before code.

- Plans live in `plans/YYYY-MM-DD_short-title.md`. The folder is gitignored and local only.
- **Claude Code** writes plan-mode files there automatically (`plansDirectory` in
  `.claude/settings.json`); rename the file to the date/slug form once the plan is accepted.
- **Codex** writes the plan file there itself before implementing.
- If the plan changes materially mid-task, update the plan file and say so in the task note.

## Task notes (required)

The task note is the durable handoff between sessions and between agents. If usage runs out
mid-task, the other agent resumes from the note alone, so keep it current.

1. **When a plan is accepted:** copy [`notes/_TEMPLATE.md`](notes/_TEMPLATE.md) to
   `notes/YYYY-MM-DD_short-title.md` **before writing any code**. Set `Status: In progress`, the
   branch, the plan path, and `Last updated: <time> — <claude|codex>`.
2. **Update the note:**
   - after each PR-sized step or commit that changes the picture;
   - when the plan changes;
   - before any risky or external operation (GitHub settings, merges, runner changes);
   - **whenever you might stop: usage running low, end of session, waiting on the user.**

   Each update leaves **Next step** and **How to resume** exact enough to continue with zero
   other context, and records dead ends so they are not retried.
3. **Statuses:** `In progress`, `Blocked` (name the blocker), `Complete`, `Abandoned` (so the
   session-start scan stops surfacing it).
4. **When done:** fill in What changed, Decisions and Verification; delete the Handoff section;
   set `Status: Complete`.
5. Notes are local and gitignored. **Never commit them**, and never paste secrets into them.

---

## Branching and releases

| Branch | Purpose |
|---|---|
| `main` | Released code only. Updated by release PRs from `develop`; every merge is tagged. |
| `develop` | Integration branch and GitHub default branch. |
| `feature/<slug>`, `fix/<slug>`, `chore/<slug>`, `docs/<slug>` | All work. Branch from an up-to-date `develop`. |

- **Never commit directly to `main` or `develop`.** Rulesets enforce PRs and a green `CI gate`.
- Start work: `git fetch origin && git switch -c feature/<slug> origin/develop`.
- Feature PRs target `develop` and are **squash-merged**.
- Release: PR `develop` → `main` (merge commit), then tag `vX.Y.Z` on `main` and push the tag.
- One cohesive change per branch; no unrelated refactors bundled in.
- Use `gh` for all PR and repo operations. Fill in `.github/pull_request_template.md`.
- Commit or push only when the user asked for it or the accepted plan includes it.

## Testing (required)

**Everything that is built ships with tests that run in CI.** A change without tests is not done.

| Layer | Location | Framework | Runs |
|---|---|---|---|
| Unit | `Tests/MailReserveKitTests/` | Swift Testing | Every engine type and function. No network, no real disk outside temp dirs. |
| Integration | `Tests/MailReserveIntegrationTests/` | Swift Testing | Anything that talks IMAP or writes the archive, against a real **GreenMail** server. |
| App | `App/MailReserveTests/`, `App/MailReserveUITests/` (from M2) | XCTest / XCUITest | View models, scheduling, key UI flows. |

Rules:
- Every bug fix adds a regression test that fails before the fix.
- Engine line coverage (`Sources/MailReserveKit`) must stay **≥ 80%**. CI enforces this with
  `scripts/ci/check-coverage.sh`.
- Integration tests are enabled when `MAILRESERVE_IMAP_TEST_HOST` is set. Locally they skip without
  it; in CI `MAILRESERVE_REQUIRE_INTEGRATION=1` turns a missing server into a failure, so they can
  never silently skip there.
- Tests use GreenMail's fake users only. **No real accounts or app passwords in tests or CI.**
  Real-account checks (milestone gates) are run by the user by hand.
- `Spike/` is the only code exempt from these rules.
- A suite is only green for the tests that actually ran: check skips covering what you changed.

Local commands:

```bash
swift build
swift test                       # unit tests (integration tests skip)
scripts/test-integration.sh      # starts GreenMail in Docker, runs integration tests
scripts/ci/check-coverage.sh 80  # after: swift test --enable-code-coverage
```

## CI (GitHub Actions)

Workflow: [`.github/workflows/ci.yml`](.github/workflows/ci.yml), on PRs and pushes to `develop`
and `main`.

| Job | Runner | What it does |
|---|---|---|
| `engine` | Self-hosted `mailreserve-ci` (ephemeral Docker, Linux arm64) for this repo's own branches; `ubuntu-latest` for fork PRs | Build, unit tests with coverage gate, GreenMail integration tests |
| `app` | GitHub-hosted `macos-latest` | macOS build and tests (Keychain adapter, app from M2) |
| `ci-gate` | Same routing as `engine` | Fails unless every job succeeded. **The only required check.** |

- Runner routing reads the repo variable `CI_RUNNER`. Deleting it (`gh variable delete CI_RUNNER`)
  sends new runs to GitHub-hosted runners; this is the escape hatch if the local fleet is down.
- Fork PRs never run on the self-hosted runner (it executes on the owner's Mac). Do not change
  the routing expression without preserving that.
- The runner fleet is defined in `scripts/self-hosted-runner/` (see its README). Changing runner
  files is a CI change: run the full pipeline before merging.
- **Never merge red.** Retry only with evidence: code or assertion failures need a code change.
  One unchanged-SHA rerun is allowed for an unexplained infrastructure failure. If it repeats, stop
  and investigate. Record the run ID, attempt and SHA in the PR and the task note.

## Swift conventions

- Swift 6 language mode, strict concurrency, `async/await`. Minimum macOS 14.
- Every file starts with a short header comment saying what it is for. Comment non-obvious logic
  (IMAP quirks, Gmail behaviour, crash-safety ordering). The owner is learning Swift, so prefer
  clarity over cleverness.
- Keep files small and single-purpose. Put protocols at the boundaries (IMAP client, credential
  store, clock, file system) so the engine is unit-testable.
- Platform-specific code goes behind `#if canImport(...)` in its own adapter file, never mixed
  into engine logic.
- Dependencies: `swift-nio-imap`, `GRDB.swift`, `swift-argument-parser`. Ask before adding others.

## Security and data safety

- Never commit secrets, `.env` files, real mail, archives or `*.sqlite` files.
- App passwords live only in the macOS Keychain. Never log them, never write them to disk, never
  put them in notes or plans.
- TLS certificate verification is always on in production code. Disabling it is allowed only in
  test configuration for GreenMail's self-signed certificate.
- Logs must not contain message bodies or credentials. Subjects and addresses only where needed.
- Fetch with `BODY.PEEK[]` so backups never change read flags on the server.

## Documentation

- When user-visible behaviour, setup, CLI usage or requirements change, update `README.md` in the
  same PR.
- Keep inline comments accurate when changing code they describe.
