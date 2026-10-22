#!/usr/bin/env bash
# Keep the bounded ephemeral runner fleet registered and observable.
# Adapted from djask12/certifyrapp scripts/self-hosted-runner/supervise.sh.
set -uo pipefail

REPO="${REPO:-djask12/mailreserve}"
IMAGE="${IMAGE:-mailreserve-runner:2.338.0}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLL_SECONDS="${POLL_SECONDS:-20}"
COMMAND_TIMEOUT_SECONDS="${COMMAND_TIMEOUT_SECONDS:-30}"
BUILD_TIMEOUT_SECONDS="${BUILD_TIMEOUT_SECONDS:-600}"
REGISTRATION_TIMEOUT_SECONDS="${REGISTRATION_TIMEOUT_SECONDS:-30}"
HEARTBEAT_SECONDS="${HEARTBEAT_SECONDS:-300}"
RUNNER_LOG_DIR="${RUNNER_LOG_DIR:-/tmp}"
TIMEOUT="$DIR/run_with_timeout.py"
INVENTORY="$DIR/runner_inventory.py"

# label:launcher:desired. At maximum concurrency this is 8 host CPUs (2 x 4).
# These are --cpus limits, not reservations, so they can overlap with other fleets.
FLEET=(
  "mailreserve-ci:run-runner.sh:${CI_RUNNERS:-2}"
)

# Never delete a registration that this supervisor does not own.
OWNED_PREFIX="mailreserve-"
LAST_STATE=""
LAST_HEARTBEAT_EPOCH=0
RUNNER_SEQUENCE=0
CURRENT_HAVE=0

log() { printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }
epoch_now() { date +%s; }

bounded() {
  python3 "$TIMEOUT" "$1" "${@:2}"
}

source_hash() {
  cat "$DIR/Dockerfile" "$DIR/entrypoint.sh" "$DIR/run_with_timeout.py" \
    | shasum -a 256 | cut -d' ' -f1
}

ensure_image() {
  local want current status
  want="$(source_hash)" || return 1
  current="$(bounded "$COMMAND_TIMEOUT_SECONDS" docker image inspect "$IMAGE" \
    --format '{{ index .Config.Labels "mailreserve.srchash" }}' 2>/dev/null)"
  status=$?
  if [ "$status" -eq 0 ] && [ "$current" = "$want" ]; then
    return 0
  fi
  if [ "$status" -eq 124 ]; then
    log "event=command_timeout command=docker_image_inspect"
    return 1
  fi
  if [ "$status" -eq 0 ]; then
    log "event=image_build reason=stale hash=$want"
  else
    log "event=image_build reason=missing hash=$want"
  fi
  bounded "$BUILD_TIMEOUT_SECONDS" docker build \
    --label "mailreserve.srchash=$want" -t "$IMAGE" "$DIR" >/dev/null
  status=$?
  if [ "$status" -eq 0 ]; then
    log "event=image_ready image=$IMAGE hash=$want"
    return 0
  fi
  log "event=image_build_failed image=$IMAGE exit=$status"
  return 1
}

fetch_runner_inventory() {
  local raw
  raw="$(bounded "$COMMAND_TIMEOUT_SECONDS" gh api --paginate --slurp \
    "repos/$REPO/actions/runners?per_page=100")" || return 1
  printf '%s' "$raw" | python3 "$INVENTORY" normalize
}

online_for_label() {
  printf '%s' "$1" | python3 "$INVENTORY" online-count --label "$2"
}

prune_offline() {
  local inventory="$1" ids id
  ids="$(printf '%s' "$inventory" | python3 "$INVENTORY" \
    offline-ids --owned-prefix "$OWNED_PREFIX")" || return 1
  for id in $ids; do
    if bounded "$COMMAND_TIMEOUT_SECONDS" gh api -X DELETE \
      "repos/$REPO/actions/runners/$id" >/dev/null; then
      log "event=runner_pruned id=$id"
    else
      log "event=runner_prune_failed id=$id"
    fi
  done
}

launch_runner() {
  local label="$1" script="$2" name="$3" log_path
  mkdir -p "$RUNNER_LOG_DIR" || return 1
  log_path="$RUNNER_LOG_DIR/$name.log"
  nohup env RUNNER_NAME="$name" bash "$DIR/$script" >"$log_path" 2>&1 &
  log "event=runner_start label=$label name=$name log=$log_path"
}

wait_for_registration() {
  bounded "$REGISTRATION_TIMEOUT_SECONDS" bash "$DIR/wait-for-registration.sh" "$1" "$2"
}

replenish_label() {
  local label="$1" script="$2" desired="$3" have="$4" name
  CURRENT_HAVE="$have"
  while [ "$CURRENT_HAVE" -lt "$desired" ]; do
    RUNNER_SEQUENCE=$((RUNNER_SEQUENCE + 1))
    name="$label-$(date +%s)-$$-$RUNNER_SEQUENCE"
    if ! launch_runner "$label" "$script" "$name"; then
      log "event=runner_start_failed label=$label name=$name"
      return 1
    fi
    if ! wait_for_registration "$name" "$label"; then
      log "event=runner_registration_unconfirmed label=$label name=$name"
      return 1
    fi
    CURRENT_HAVE=$((CURRENT_HAVE + 1))
    log "event=runner_registered label=$label name=$name online=$CURRENT_HAVE/$desired"
  done
}

report_state() {
  local state="$1" now
  if [ "$state" != "$LAST_STATE" ]; then
    log "event=state $state"
    LAST_STATE="$state"
  fi
  now="$(epoch_now)" || return 1
  if [ "$LAST_HEARTBEAT_EPOCH" -eq 0 ] \
    || [ $((now - LAST_HEARTBEAT_EPOCH)) -ge "$HEARTBEAT_SECONDS" ]; then
    log "event=heartbeat $state"
    LAST_HEARTBEAT_EPOCH="$now"
  fi
}

validate_fleet() {
  local entry label script desired
  for entry in "${FLEET[@]}"; do
    IFS=: read -r label script desired <<<"$entry"
    case "$desired" in
      ''|*[!0-9]*) log "event=configuration_error label=$label desired=$desired"; return 1 ;;
    esac
    if [ "$desired" -lt 0 ] || [ ! -x "$DIR/$script" ]; then
      log "event=configuration_error label=$label launcher=$script desired=$desired"
      return 1
    fi
  done
}

run_cycle() {
  local inventory entry label script desired have fleet_state="" registration_failed=0

  if ! bounded "$COMMAND_TIMEOUT_SECONDS" docker info >/dev/null; then
    report_state "docker=unavailable image=unknown inventory=unknown fleet=unknown"
    return 0
  fi
  if ! ensure_image; then
    report_state "docker=ready image=unavailable inventory=unknown fleet=unknown"
    return 0
  fi
  if ! inventory="$(fetch_runner_inventory)"; then
    log "event=inventory_unavailable action=launch_none"
    report_state "docker=ready image=ready inventory=unavailable fleet=unknown"
    return 0
  fi

  prune_offline "$inventory" || log "event=offline_prune_incomplete"
  for entry in "${FLEET[@]}"; do
    IFS=: read -r label script desired <<<"$entry"
    have="$(online_for_label "$inventory" "$label")"
    if [ "$?" -ne 0 ]; then
      log "event=inventory_query_failed label=$label action=launch_none"
      report_state "docker=ready image=ready inventory=invalid fleet=unknown"
      return 0
    fi
    if ! replenish_label "$label" "$script" "$desired" "$have"; then
      registration_failed=1
    fi
    if [ -n "$fleet_state" ]; then
      fleet_state="$fleet_state,"
    fi
    fleet_state="$fleet_state$label=$CURRENT_HAVE/$desired"
  done
  report_state "docker=ready image=ready inventory=ready fleet=$fleet_state registration_failed=$registration_failed"
}

main() {
  validate_fleet || return 1
  log "event=supervisor_started fleet=${FLEET[*]}"
  while true; do
    run_cycle
    sleep "$POLL_SECONDS"
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
