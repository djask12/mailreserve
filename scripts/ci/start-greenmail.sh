#!/usr/bin/env bash
# Start a GreenMail IMAP/SMTP test server as a background Java process and wait until it accepts
# connections. Used by CI (self-hosted Docker runner and ubuntu-latest); needs Java 17+.
#
# GreenMail runs inside the job rather than as a `services:` container because the self-hosted
# runner is itself a container: a services container would need the host Docker socket mounted
# into the runner, which would hand every CI job root on the host Mac.
#
# Ports (GreenMail "test" setup): IMAP 3143, IMAPS 3993, SMTP 3025.
# Users: one fake account, test@localhost / test-password. Never a real account.
set -euo pipefail

GREENMAIL_VERSION="2.1.14"
GREENMAIL_SHA256="0381392f3a44e4d8ae78051778440f58820d01acaf5757c3f43649deda8c1d23"
CACHE_DIR="${GREENMAIL_CACHE_DIR:-.ci-cache}"
JAR="$CACHE_DIR/greenmail-standalone-$GREENMAIL_VERSION.jar"
URL="https://repo1.maven.org/maven2/com/icegreen/greenmail-standalone/$GREENMAIL_VERSION/greenmail-standalone-$GREENMAIL_VERSION.jar"
LOG="$CACHE_DIR/greenmail.log"

mkdir -p "$CACHE_DIR"
if [ ! -f "$JAR" ]; then
  curl -fsSL -o "$JAR.tmp" "$URL"
  mv "$JAR.tmp" "$JAR"
fi

# sha256sum on Linux, shasum on macOS.
if command -v sha256sum >/dev/null; then
  actual="$(sha256sum "$JAR" | cut -d' ' -f1)"
else
  actual="$(shasum -a 256 "$JAR" | cut -d' ' -f1)"
fi
if [ "$actual" != "$GREENMAIL_SHA256" ]; then
  echo "error: GreenMail jar checksum mismatch ($actual)" >&2
  rm -f "$JAR"
  exit 1
fi

nohup java \
  -Dgreenmail.setup.test.all \
  -Dgreenmail.hostname=127.0.0.1 \
  -Dgreenmail.users=test:test-password@localhost \
  -Dgreenmail.users.login=email \
  -jar "$JAR" >"$LOG" 2>&1 &
echo $! >"$CACHE_DIR/greenmail.pid"

# Wait up to 60s for the IMAP port; bash's /dev/tcp avoids needing nc.
for _ in $(seq 1 60); do
  if (exec 3<>/dev/tcp/127.0.0.1/3143) 2>/dev/null; then
    echo "GreenMail $GREENMAIL_VERSION is up (pid $(cat "$CACHE_DIR/greenmail.pid"))"
    exit 0
  fi
  sleep 1
done
echo "error: GreenMail did not start; log follows" >&2
cat "$LOG" >&2
exit 1
