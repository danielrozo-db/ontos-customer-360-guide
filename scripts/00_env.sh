#!/usr/bin/env bash
# =============================================================================
# 00_env.sh — Shared environment, auth, and helpers for the Bricks&Co Ontos guide
# =============================================================================
# Source this from every other script:   source "$(dirname "$0")/00_env.sh"
#
# It provides:
#   * BASE_URL / TOKEN            — how we reach and authenticate to Ontos
#   * api_get / api_post / api_delete — thin curl wrappers with error handling
#   * find_id_by_name             — idempotent "does it already exist?" lookups
#   * save_state / load_state     — persist created IDs across scripts
#
# Every create in this guide is idempotent: re-running a script reuses the
# resource it created last time instead of making a duplicate.
# =============================================================================
set -euo pipefail

# --- Configuration (override via environment if needed) ----------------------
# The live Bricks&Co Ontos Databricks App:
export BASE_URL="${BASE_URL:-https://ontos-<your-workspace-id>.aws.databricksapps.com}"
# Databricks CLI profile used to mint an OAuth token for the app:
export DATABRICKS_PROFILE="${DATABRICKS_PROFILE:-ontos}"

# Naming — everything this guide creates is prefixed so it never collides with
# other resources already in the workspace.
export ONTOS_TENANT="${ONTOS_TENANT:-BricksAndCoInc}"
export TAG_NAMESPACE="${TAG_NAMESPACE:-bricksco}"
export DOMAIN_NAME="${DOMAIN_NAME:-Bricks&Co Customer Core}"
export TEAM_NAME="${TEAM_NAME:-Bricks&Co Customer Team}"
export PROJECT_NAME="${PROJECT_NAME:-Bricks&Co Customer 360 Project}"
export CONTRACT_NAME="${CONTRACT_NAME:-Customer 360 Profile}"
export PRODUCT_NAME="${PRODUCT_NAME:-Customer 360 Profile}"
# Whoever runs this becomes the team owner (needed so contract/product creation,
# which requires project membership, succeeds).
export OWNER_EMAIL="${OWNER_EMAIL:-$(databricks auth token -p "$DATABRICKS_PROFILE" >/dev/null 2>&1 && \
  curl -sS -H "Authorization: Bearer $(databricks auth token -p "$DATABRICKS_PROFILE" | jq -r .access_token)" \
  "$BASE_URL/api/user/info" | jq -r .email)}"

# Physical target the data product's output port points at (must match the DAB):
export UC_CATALOG="${UC_CATALOG:-bricks_co}"
export UC_SCHEMA="${UC_SCHEMA:-customer_360}"
export UC_TABLE="${UC_TABLE:-customer_360_profile}"

# State file that carries created IDs between scripts.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export STATE_FILE="${STATE_FILE:-$SCRIPT_DIR/.ontos_state.env}"

# --- Tooling checks ----------------------------------------------------------
for bin in curl jq databricks; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: '$bin' is required but not on PATH." >&2; exit 1; }
done

# --- Auth --------------------------------------------------------------------
# Mint a fresh OAuth token for the app. Databricks Apps accept the workspace
# user's OAuth token; the Apps proxy injects the x-forwarded-* identity headers.
mint_token() {
  local t
  t="$(databricks auth token -p "$DATABRICKS_PROFILE" 2>/dev/null | jq -r '.access_token // empty')"
  if [[ -z "$t" ]]; then
    echo "ERROR: could not mint a token from profile '$DATABRICKS_PROFILE'." >&2
    echo "       Run:  databricks auth login -p $DATABRICKS_PROFILE" >&2
    exit 1
  fi
  printf '%s' "$t"
}
export TOKEN="${TOKEN:-$(mint_token)}"

# --- HTTP helpers ------------------------------------------------------------
# All helpers print the JSON response body to stdout and fail (non-zero) on a
# non-2xx status, printing the status + body to stderr.
_api() {
  local method="$1" path="$2" body="${3:-}"
  local tmp code
  tmp="$(mktemp)"
  if [[ -n "$body" ]]; then
    code="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      --data "$body" "$BASE_URL$path")"
  else
    code="$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $TOKEN" "$BASE_URL$path")"
  fi
  if [[ "$code" -lt 200 || "$code" -ge 300 ]]; then
    echo "HTTP $code on $method $path" >&2
    cat "$tmp" >&2; echo >&2
    rm -f "$tmp"
    return 1
  fi
  cat "$tmp"; rm -f "$tmp"
}
api_get()    { _api GET    "$1"; }
api_post()   { _api POST   "$1" "$2"; }
api_put()    { _api PUT    "$1" "$2"; }
api_delete() { _api DELETE "$1"; }

# --- State helpers -----------------------------------------------------------
save_state() { # save_state KEY VALUE
  # Sanitize: keep only the first line and trim whitespace so a stray multi-line
  # capture can never corrupt the sourced state file.
  local val
  val="$(printf '%s' "$2" | head -n1 | tr -d '[:space:]')"
  touch "$STATE_FILE"
  grep -v "^$1=" "$STATE_FILE" > "$STATE_FILE.tmp" 2>/dev/null || true
  mv "$STATE_FILE.tmp" "$STATE_FILE" 2>/dev/null || true
  echo "$1=$val" >> "$STATE_FILE"
}
load_state() { [[ -f "$STATE_FILE" ]] && set -a && source "$STATE_FILE" && set +a || true; }

# find_id_by_name LIST_JSON NAME  -> prints the .id of the first element whose
# .name equals NAME (exact), else empty.
find_id_by_name() {
  jq -r --arg n "$2" 'map(select(.name == $n)) | (.[0].id // empty)' <<<"$1"
}

load_state
