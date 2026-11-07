#!/usr/bin/env bash
# Caudals customer API helper (https://app.caudals.com, Settings -> Developers).
#
# Environment:
#   CAUDALS_TOKEN   customer API token (evct_...), kept secret
#   CAUDALS_ORG_ID  workspace ID
#   CAUDALS_API     optional, default https://app.caudals.com/api/evals/v1
#
# Needs bash, curl and jq. The token is passed to curl on standard input, never
# on the command line, and is never printed.
set -euo pipefail

API="${CAUDALS_API:-https://app.caudals.com/api/evals/v1}"
API="${API%/}"
UUID_RE='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

usage() {
  cat <<'EOF'
Usage: caudals.sh <command> [arguments]

Read (runs:read, reports:read or schedules:read):
  runs                                   the 100 newest runs
  reports                                the 100 most recently updated published reports
  schedules                              the 100 most recently updated monitoring schedules
  schedule-status <scheduleId>           latest outcome of a schedule (pass, regression, inconclusive, unknown, pending)
  estimate <evaluationId> [suiteVersionId] [targetRevisionId]
                                         credits (p50, p90), time and balance for a run
  gate <runId>                           release gate of a run (pass, fail, unknown, pending)
  wait-gate <runId> [timeoutSeconds]     poll the gate until it is not pending (default 3600 s)
                                         exit 0 pass, 1 fail, 2 unknown, 3 timed out

Write (runs:write; spends credits):
  start-run <suiteVersionId> <targetRevisionId> <idempotencyKey> [evaluationId]
                                         start one run; the same key always returns the same run

Environment: CAUDALS_TOKEN, CAUDALS_ORG_ID, optional CAUDALS_API.
EOF
}

die() { printf 'caudals: %s\n' "$*" >&2; exit 64; }

need() {
  command -v curl >/dev/null 2>&1 || die "curl is required"
  command -v jq >/dev/null 2>&1 || die "jq is required"
  [ -n "${CAUDALS_TOKEN:-}" ] || die "set CAUDALS_TOKEN (create one in Settings -> Developers)"
  [ -n "${CAUDALS_ORG_ID:-}" ] || die "set CAUDALS_ORG_ID (the Workspace ID in Settings -> Developers)"
  [[ "$CAUDALS_TOKEN" =~ ^evct_[A-Za-z0-9_-]{43}$ ]] || die "CAUDALS_TOKEN does not look like a Caudals token (evct_ followed by 43 characters)"
  [[ "$CAUDALS_ORG_ID" =~ $UUID_RE ]] || die "CAUDALS_ORG_ID must be a UUID"
}

uuid() { [[ "${2:-}" =~ $UUID_RE ]] || die "$1 must be a UUID"; printf '%s' "$2"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# request METHOD PATH [JSON_BODY] [IDEMPOTENCY_KEY]
# Sets STATUS and RETRY_AFTER; the body is left in $TMP/body.
request() {
  local method="$1" path="$2" body="${3:-}" key="${4:-}"
  local -a args=(-sS -X "$method" -o "$TMP/body" -D "$TMP/headers" -w '%{http_code}'
    -H 'Accept: application/json' -H 'User-Agent: caudals-evals-skill/1.0')
  if [ -n "$body" ]; then args+=(-H 'Content-Type: application/json' --data-binary "$body"); fi
  if [ -n "$key" ]; then args+=(-H "Idempotency-Key: $key"); fi
  STATUS="$(printf 'header = "Authorization: Bearer %s"\n' "$CAUDALS_TOKEN" | curl -K - "${args[@]}" "$API$path")" || die "request failed: $method $path"
  RETRY_AFTER="$(awk 'tolower($1)=="retry-after:" {gsub("\r",""); print $2}' "$TMP/headers" | tail -n 1)"
}

# Prints the body; on an HTTP error prints it to stderr and exits 1.
emit() {
  if [ "$STATUS" -ge 400 ]; then
    { printf 'caudals: HTTP %s' "$STATUS"; [ -n "$RETRY_AFTER" ] && printf ' (retry after %s s)' "$RETRY_AFTER"; printf '\n'
      jq . "$TMP/body" 2>/dev/null || cat "$TMP/body"; } >&2
    exit 1
  fi
  jq . "$TMP/body"
}

org_q() { printf 'orgId=%s' "$CAUDALS_ORG_ID"; }

cmd="${1:-}"
[ $# -gt 0 ] && shift
case "$cmd" in
  runs|reports|schedules)
    need; request GET "/integrations/$cmd?$(org_q)"; emit ;;
  schedule-status)
    need; id="$(uuid scheduleId "${1:-}")"
    request GET "/integrations/ci/$id?$(org_q)"; emit ;;
  estimate)
    need; ev="$(uuid evaluationId "${1:-}")"
    suite=""; target=""
    [ -n "${2:-}" ] && suite="$(uuid suiteVersionId "$2")"
    [ -n "${3:-}" ] && target="$(uuid targetRevisionId "$3")"
    body="$(jq -nc --arg o "$CAUDALS_ORG_ID" --arg e "$ev" --arg s "$suite" --arg t "$target" \
      '{orgId:$o,evaluationId:$e} + (if $s=="" then {} else {suiteVersionId:$s} end) + (if $t=="" then {} else {targetRevisionId:$t} end)')"
    request POST "/billing/estimates" "$body" "estimate-$(date +%s)-$$"; emit ;;
  start-run)
    need; suite="$(uuid suiteVersionId "${1:-}")"; target="$(uuid targetRevisionId "${2:-}")"; key="${3:-}"
    [[ "$key" =~ ^[!-~]{8,200}$ ]] || die "idempotencyKey must be 8-200 visible ASCII characters, the same on every retry"
    ev=""; [ -n "${4:-}" ] && ev="$(uuid evaluationId "$4")"
    body="$(jq -nc --arg s "$suite" --arg t "$target" --arg e "$ev" \
      '{suiteVersionId:$s,targetRevisionId:$t} + (if $e=="" then {} else {evaluationId:$e} end)')"
    request POST "/integrations/runs?$(org_q)" "$body" "$key"; emit ;;
  gate)
    need; id="$(uuid runId "${1:-}")"
    request GET "/integrations/runs/$id/gate?$(org_q)"; emit ;;
  wait-gate)
    need; id="$(uuid runId "${1:-}")"; timeout="${2:-3600}"
    [[ "$timeout" =~ ^[0-9]+$ ]] || die "timeoutSeconds must be a whole number"
    deadline=$(( $(date +%s) + timeout ))
    while :; do
      request GET "/integrations/runs/$id/gate?$(org_q)"
      if [ "$STATUS" = "429" ]; then
        wait="${RETRY_AFTER:-30}"; note="rate limited"
      else
        [ "$STATUS" -ge 400 ] && emit
        status="$(jq -r '.data.status' "$TMP/body")"
        if [ "$status" != "pending" ]; then
          jq '.data' "$TMP/body"
          case "$status" in pass) exit 0 ;; fail) exit 1 ;; *) exit 2 ;; esac
        fi
        wait="${RETRY_AFTER:-30}"
        note="pending: $(jq -r '.data.reason_codes // [] | join(",")' "$TMP/body" 2>/dev/null)"
      fi
      [[ "$wait" =~ ^[0-9]+$ ]] || wait=30
      if [ $(( $(date +%s) + wait )) -gt "$deadline" ]; then
        printf 'caudals: gate still pending after %s s\n' "$timeout" >&2
        jq '.data' "$TMP/body" >&2 2>/dev/null || true
        exit 3
      fi
      printf 'caudals: gate %s, checking again in %s s\n' "$note" "$wait" >&2
      sleep "$wait"
    done ;;
  ""|-h|--help|help)
    usage ;;
  *)
    usage >&2; exit 64 ;;
esac
