#!/usr/bin/env bash
# Run the integration tests locally against a throwaway GreenMail server in Docker.
#   scripts/test-integration.sh            # all integration tests
#   scripts/test-integration.sh <filter>   # extra `swift test --filter` expression
set -euo pipefail

IMAGE="greenmail/standalone:2.1.14"
NAME="mailreserve-greenmail-$$"

cd "$(dirname "$0")/.."

docker run -d --rm --name "$NAME" \
  -p 127.0.0.1:3143:3143 -p 127.0.0.1:3993:3993 -p 127.0.0.1:3025:3025 \
  -e GREENMAIL_OPTS="-Dgreenmail.setup.test.all -Dgreenmail.hostname=0.0.0.0 -Dgreenmail.users=test:test-password@localhost -Dgreenmail.users.login=email" \
  "$IMAGE" >/dev/null
trap 'docker stop "$NAME" >/dev/null 2>&1 || true' EXIT

for _ in $(seq 1 60); do
  if (exec 3<>/dev/tcp/127.0.0.1/3143) 2>/dev/null && docker logs "$NAME" 2>&1 | grep -q "Started"; then
    break
  fi
  sleep 1
done

export MAILRESERVE_IMAP_TEST_HOST=127.0.0.1
export MAILRESERVE_REQUIRE_INTEGRATION=1
swift test --filter "MailReserveIntegrationTests${1:+.*$1}"
