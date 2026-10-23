# M0 IMAP spike

A throwaway command-line tool that proves [swift-nio-imap](https://github.com/apple/swift-nio-imap)
works with real Gmail and Yahoo accounts before the backup engine (M1) is built on it. Delete this
folder once the gate below passes.

For one account, it:
1. connects over TLS (port 993) and logs in with your app password from the macOS Keychain;
2. lists every folder;
3. opens one folder **read-only** (`EXAMINE`), so read/unread flags never change;
4. downloads the newest N messages with `BODY.PEEK[]`, streaming each one to
   `spike-output/<email>/<folder>/<uid>.eml`;
5. writes `spike-output/<email>/report.txt`, covering capabilities, folders, UIDVALIDITY, sizes,
   Gmail message IDs and labels, and timing.

`spike-output/` is gitignored. It contains your real mail, so never commit or share it.

## 1. Create app passwords

Follow the README's [Create an app password](../README.md#1-create-an-app-password) steps for
Gmail and Yahoo.

## 2. Store them in the Keychain

Run this in Terminal for each account, then paste the app password when prompted. It isn't shown
on screen and doesn't go into your shell history. Spaces in Google's app passwords are fine.

```bash
security add-generic-password -s mailreserve-spike -a you@gmail.com -w
security add-generic-password -s mailreserve-spike -a you@yahoo.com -w
```

The first time the spike reads a password, macOS asks whether `imap-spike` may use it. Click
**Allow**. After the spike is rebuilt, macOS may ask again.

## 3. Run the spike

From the repository root:

```bash
swift run --package-path Spike imap-spike gmail you@gmail.com
swift run --package-path Spike imap-spike yahoo you@yahoo.com
```

Options:

| Option | Default | Meaning |
|---|---|---|
| `--count N` | `100` | How many of the newest messages to download |
| `--folder NAME` | `INBOX` | Folder to download from, named as in the report's folder list (e.g. `[Gmail]/Sent Mail`) |
| `--list-only` | off | Only log in and list folders |
| `--output DIR` | `spike-output` | Where files and reports go |

A server other than Gmail or Yahoo can be given as `host` or `host:port` (TLS only).

## 4. The gate

M0 passes when, for **both** accounts:

- [ ] the spike finishes with `Size mismatches: 0` and `messages without UID: 0`;
- [ ] in Finder, opening `spike-output/<email>/INBOX/`, selecting all the `.eml` files and pressing
      ⌘O opens them in Apple Mail;
- [ ] spot-checked messages show the right sender, subject, date and body, including HTML mail,
      non-English text and attachments (open or Quick Look at least one attachment);
- [ ] the messages are still unread or read on the server exactly as before.

Then share `report.txt` from each account (it has folder names, sizes and IDs but no message
content) so that M1 can be designed around what the servers actually do.

## Uninstalling

When the spike is done, remove the stored passwords:

```bash
security delete-generic-password -s mailreserve-spike -a you@gmail.com
security delete-generic-password -s mailreserve-spike -a you@yahoo.com
```

## Testing locally (developers)

Against a local GreenMail server, with a fake account:

```bash
docker run -d --rm --name greenmail -p 127.0.0.1:3143:3143 -p 127.0.0.1:3025:3025 \
  -e GREENMAIL_OPTS="-Dgreenmail.setup.test.all -Dgreenmail.hostname=0.0.0.0 -Dgreenmail.users=test:test-password@localhost -Dgreenmail.users.login=email" \
  greenmail/standalone:2.1.14
# send it some mail over SMTP on port 3025, then:
swift run --package-path Spike imap-spike 127.0.0.1:3143 test@localhost --plaintext --test-password test-password
```

`--plaintext` and `--test-password` are refused for any host other than localhost.
