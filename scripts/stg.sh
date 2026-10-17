#!/usr/bin/env bash
# Staging stack: ./stg.sh <up|down|status|logs|smoke>
set -euo pipefail

TARGET=stg

usage() {
  cat >&2 <<'USAGE'
Usage: ./stg.sh <command>

Commands:
  up      start the stack and wait until it is healthy (safe to rerun)
  down    stop and remove the containers, keep the database volume
  status  show service health and call the API /health (exit 1 if unhealthy)
  logs    show the last API log lines (TAIL=200 for more, FOLLOW=1 to follow)
  smoke   create a user and a notification, then read them back

Note: stg images are public, no login needed.
USAGE
  exit "${1:-2}"
}

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*" >&2; }

if [ $# -ne 1 ]; then usage; fi
case "$1" in -h|--help|help) usage 0 ;; esac
CMD=$1

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

PROJECT="spare-$TARGET"
FILE="docker-compose-$TARGET.yml"
API_URL=${API_URL:-http://127.0.0.1:8080}
LOG_FILE=""
trap 'if [ -n "$LOG_FILE" ]; then rm -f "$LOG_FILE"; fi' EXIT

command -v docker >/dev/null 2>&1 || die "docker not found. Install Docker Desktop (or Docker Engine) and retry."
docker compose version >/dev/null 2>&1 || die "'docker compose' (v2) is not available. Update Docker and retry."
docker info >/dev/null 2>&1 || die "the Docker daemon is not reachable. Start Docker Desktop and retry."
[ -f "$FILE" ] || die "$FILE not found in $ROOT."
[ -f .env ] || die ".env not found in $ROOT. Create it with DB_NAME, DB_USER and DB_PASSWORD."

compose() { docker compose -f "$FILE" "$@"; }
need_curl() { command -v curl >/dev/null 2>&1 || die "curl not found. Install curl and retry."; }

# Both stacks publish 127.0.0.1:8080, so only one can run at a time
check_port_owner() {
  local other=stg
  [ "$TARGET" = stg ] && other=prod
  if [ -n "$(docker ps -q --filter "label=com.docker.compose.project=spare-$other")" ]; then
    die "spare-$other is running and also uses port 8080. Stop it first: ./$other.sh down"
  fi
}

cmd_up() {
  check_port_owner
  info "Starting $PROJECT (pull images, wait for healthchecks)"
  LOG_FILE=$(mktemp)
  if ! compose up -d --wait --wait-timeout 120 2>&1 | tee "$LOG_FILE"; then
    if grep -qiE 'unauthorized|denied|authentication required' "$LOG_FILE"; then
      if [ "$TARGET" = prod ]; then
        die "the registry refused the pull. prod images are private: run 'docker login ghcr.io -u <github-user>' with a classic PAT that has read:packages, then retry."
      fi
      die "the registry refused the pull. stg images are public: an expired stored login can cause this, run 'docker logout ghcr.io' and retry."
    fi
    die "$PROJECT did not become healthy. Check './$TARGET.sh status' and './$TARGET.sh logs'."
  fi
  info "$PROJECT is up on $API_URL"
}

cmd_down() {
  info "Stopping $PROJECT (the database volume is kept)"
  compose down
}

cmd_status() {
  need_curl
  local svc row state health failed=0 resp
  printf '%-8s %-10s %s\n' SERVICE STATE HEALTH
  for svc in db api; do
    row=$(compose ps -a --format '{{.State}} {{.Health}}' "$svc" 2>/dev/null || true)
    state=${row%% *}
    health=${row#* }
    [ -n "$row" ] || { state=missing; health=-; }
    printf '%-8s %-10s %s\n' "$svc" "$state" "${health:--}"
    if [ "$state" != running ] || [ "$health" != healthy ]; then failed=1; fi
  done
  [ "$failed" -eq 0 ] || die "$PROJECT is not healthy. Start it with './$TARGET.sh up' or check './$TARGET.sh logs'."

  if resp=$(curl -fsS --max-time 5 "$API_URL/health" 2>&1) && [[ $resp == *'"status":"ok"'* ]]; then
    printf '%-8s %s\n' API "$API_URL/health -> $resp"
  else
    die "API health check failed at $API_URL/health: ${resp:-no response}"
  fi
  info "$PROJECT is healthy"
}

cmd_logs() {
  local args=(--tail "${TAIL:-100}" --timestamps)
  if [ "${FOLLOW:-0}" = 1 ]; then args+=(--follow); fi
  compose logs "${args[@]}" api
}

# request METHOD PATH [JSON]: sets RESPONSE, fails on a non-2xx status
RESPONSE=""
request() {
  local method=$1 path=$2 data=${3:-} out code
  local args=(-sS --max-time 10 -X "$method" -w '\n%{http_code}')
  if [ -n "$data" ]; then args+=(-H 'Content-Type: application/json' -d "$data"); fi
  out=$(curl "${args[@]}" "$API_URL$path") \
    || die "cannot reach $API_URL ($method $path). Is the stack up? './$TARGET.sh status'"
  code=${out##*$'\n'}
  RESPONSE=${out%$'\n'*}
  case "$code" in
    2??) ;;
    *) die "$method $path returned HTTP $code: $RESPONSE" ;;
  esac
}

# First "id" field of a JSON object ("user_id" does not match)
first_id() { { grep -o '"id":[0-9]*' <<<"$1" || true; } | head -n 1 | cut -d: -f2; }

cmd_smoke() {
  need_curl
  local name user_id notif_id count
  name="smoke-$(date +%s)"
  info "Smoke test against $API_URL ($PROJECT)"

  request GET /health
  [[ $RESPONSE == *'"status":"ok"'* ]] || die "GET /health did not report ok: $RESPONSE"
  echo "ok   GET /health"

  request POST /users "{\"name\":\"$name\"}"
  user_id=$(first_id "$RESPONSE")
  [ -n "$user_id" ] || die "POST /users returned no id: $RESPONSE"
  echo "ok   POST /users -> id $user_id ($name)"

  request POST /notifications "{\"user_id\":$user_id,\"title\":\"smoke\",\"body\":\"smoke test\"}"
  notif_id=$(first_id "$RESPONSE")
  [ -n "$notif_id" ] || die "POST /notifications returned no id: $RESPONSE"
  echo "ok   POST /notifications -> id $notif_id"

  request GET "/notifications?user_id=$user_id"
  count=$({ grep -o "\"user_id\":${user_id}[,}]" <<<"$RESPONSE" || true; } | wc -l | tr -d ' ')
  [ "$count" -eq 1 ] || die "expected 1 notification for user $user_id, got $count: $RESPONSE"
  grep -q "\"id\":${notif_id}[,}]" <<<"$RESPONSE" || die "notification $notif_id missing from the list: $RESPONSE"
  echo "ok   GET /notifications?user_id=$user_id -> 1 notification"

  info "Smoke test passed (test rows named $name stay in the database)"
}

case "$CMD" in
  up) cmd_up ;;
  down) cmd_down ;;
  status) cmd_status ;;
  logs) cmd_logs ;;
  smoke) cmd_smoke ;;
  *) echo "error: unknown command '$CMD'" >&2; usage ;;
esac
