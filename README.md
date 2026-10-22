# MailReserve

**Back up your Gmail and Yahoo mail to plain `.eml` files on your Mac: searchable, browsable,
and yours forever.**

[![CI](https://github.com/djask12/mailreserve/actions/workflows/ci.yml/badge.svg?branch=develop)](https://github.com/djask12/mailreserve/actions/workflows/ci.yml)
![Status: pre-alpha](https://img.shields.io/badge/status-pre--alpha-orange)
![Platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

MailReserve is a free, open source macOS app that backs up your mailboxes over IMAP into ordinary
`.eml` files you own. Think MailStore Home, but native to the Mac.

> **Status: pre-alpha.** MailReserve is under active development and is not ready to use yet.
> Steps below marked *(coming in M1–M4)* describe planned behaviour. See the [Roadmap](#roadmap).

---

## What it does

- **Never lose an email.** A complete, verifiable local copy of every account: every folder and
  Gmail label, with attachments intact.
- **Open format.** One `.eml` file per message in a readable folder tree. Apple Mail, Thunderbird
  and Outlook can open them without MailReserve.
- **Set and forget.** Incremental backups on a schedule (daily or every N hours) from the menu
  bar, with clear logs of every run.
- **Fast search** across all your accounts from one window. Double-click a message to open it in
  Mail and reply or forward.
- **Safe by design.** Messages deleted on the server are kept in your archive. Backups never
  change your read/unread flags.

### What it isn't

- Not an email client: it doesn't compose or send mail.
- No cloud backup targets, restore or migration in v1 (they're on the [roadmap](#roadmap)).
- macOS only.

## How your mail is stored

Pick any destination: your internal disk, an external drive, or a mounted NAS share.

```text
MailReserve/
  you@gmail.com/
    INBOX/2026/10/2026-10-22_Your-receipt_a1b2c3.eml
    Receipts/...
  you@yahoo.com/
    INBOX/...
  index.sqlite        ← search index; rebuildable from the .eml files at any time
```

The `.eml` files are the source of truth. If the index is ever lost, MailReserve rebuilds it by
rescanning the folder. You can always browse or copy the files yourself with Finder.

## Requirements

- macOS 14 Sonoma or later
- Xcode 16 or later, to build from source (free from the Mac App Store)
- A Gmail, Yahoo or other IMAP account, with an **app password** (below)

## 1. Create an app password

MailReserve signs in with an *app password*: a separate password just for this app, which you can
revoke at any time without changing your main password. It is stored only in your Mac's Keychain.

### Gmail

1. Turn on **2-Step Verification** for your Google account (required for app passwords):
   [myaccount.google.com/security](https://myaccount.google.com/security).
2. Go to [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords), enter a
   name such as `MailReserve`, and click **Create**.
3. Copy the 16-character password. You'll paste it into MailReserve once.

Server settings (filled in automatically): `imap.gmail.com`, port `993`, SSL/TLS.

> Work or school (Google Workspace) accounts may have app passwords disabled by an admin.

### Yahoo Mail

1. Open [Yahoo Account Security](https://login.yahoo.com/account/security).
2. Click **Generate app password** (or **Manage app passwords**), name it `MailReserve`, and click
   **Generate**.
3. Copy the password.

Server settings (filled in automatically): `imap.mail.yahoo.com`, port `993`, SSL/TLS.

### Other IMAP providers

Use your provider's IMAP host and port (usually `993` with SSL/TLS) and an app password if your
provider offers them. Outlook.com / Microsoft 365 require OAuth sign-in, which isn't supported yet.

## 2. Install (build from source)

MailReserve isn't distributed as a signed download yet, so you build it yourself. It takes a few
minutes.

```bash
# 1. Get the code
git clone https://github.com/djask12/mailreserve.git
cd mailreserve

# 2. Build and test the backup engine
swift build -c release
swift test
```

**The app** *(coming in M2)*: open `App/MailReserve.xcodeproj` in Xcode, choose the **MailReserve**
scheme and **My Mac**, then press **Run** (⌘R). To keep a copy in Applications, use
**Product → Archive → Distribute App → Copy App**.

**First launch of an unsigned app:** if macOS says the app "cannot be opened", open
**System Settings → Privacy & Security**, scroll down and click **Open Anyway**. You only do this
once. The first time MailReserve reads a saved password, macOS asks for Keychain access: click
**Always Allow**.

## 3. Your first backup *(coming in M1–M2)*

1. Click the MailReserve icon in the menu bar and choose **Settings**.
2. **Accounts → Add**: choose Gmail, Yahoo or Other, enter your address and app password, and click
   **Test connection**.
3. **Destination**: choose a folder on your disk, external drive or NAS.
4. **Folders**: untick anything you don't want backed up. Spam and Trash are skipped by default.
5. Click **Run now**. The first backup downloads everything and can take a while for large
   mailboxes. Later runs only fetch new mail.
6. **Schedule**: choose daily or every N hours. Backups run from the menu bar even when the main
   window is closed.

## Command line *(coming in M1)*

The backup engine also ships as a command-line tool:

```bash
mailreserve backup             # back up all accounts now
mailreserve verify             # compare archive counts with the server
mailreserve reindex            # rebuild the search index from the .eml files
```

## Privacy and security

- Your mail goes straight from your provider to your disk. Nothing passes through any other server.
- App passwords are stored only in the macOS Keychain.
- No telemetry, no analytics, no accounts.

## Roadmap

| Milestone | What you get |
|---|---|
| **M0** IMAP spike | Prove the IMAP library against real Gmail and Yahoo accounts |
| **M1** Backup engine | Full and incremental backups, Gmail label dedupe, resume after interruption, run logs, CLI |
| **M2** App shell | Menu bar app, settings, scheduled backups |
| **M3** Browse and search | Folder browser, message preview, full-text search in under a second, open in Mail |
| **M4** v0.1 release | Verify against the server, friendly error messages, tagged release |

After v0.1: restore to the original or another account, date-range backups, notifications, export
to `.mbox`, event-based triggers, SFTP/S3 destinations, encryption, attachment search, OAuth, and
more.

## Contributing

Contributions are welcome. Branching, testing and CI rules live in [AGENTS.md](AGENTS.md); they apply
to people and AI coding agents alike. In short:

- Branch from `develop` (`feature/<name>`) and open a pull request back into `develop`.
- Every change ships with tests (unit, plus integration tests for anything that talks IMAP or
  writes files). CI must be green before merging.

Running the tests locally:

```bash
swift test                     # unit tests
scripts/test-integration.sh    # integration tests against a local GreenMail server (needs Docker)
```

## License

[MIT](LICENSE)

## Acknowledgements

Built with [swift-nio-imap](https://github.com/apple/swift-nio-imap),
[GRDB.swift](https://github.com/groue/GRDB.swift) and
[GreenMail](https://greenmail-mail-test.github.io/greenmail/) (for testing).
