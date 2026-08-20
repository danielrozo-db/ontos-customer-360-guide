#!/usr/bin/env bash
# =============================================================================
# 10_onboard.sh — Unified Bricks&Co onboarding orchestrator
# =============================================================================
# Runs the whole guide (01..07) end to end, then layers a small multi-team org
# structure on top, parameterized by three users:
#
#   ./10_onboard.sh --admin <email> --producer <email> --consumer <email>
#
#   * admin     — added as an Admin to BOTH teams
#   * producer  — added to the Customer Team as "Data Producer"
#   * consumer  — added to the Marketing team as "Data Consumer"
#
# On top of 01..07 it also:
#   * creates the "Bricks&Co Marketing" data domain
#   * creates the "Bricks&Co Marketing" team (bound to that domain)
#   * promotes the Customer 360 Project to a TEAM project and assigns the
#     Customer Team to it
#   * removes ALL tags from the Customer Core domain
#
# Everything is idempotent: safe to re-run. It also doubles as the rebuild path
# after 99_cleanup.sh, since 01..07 recreate resources by name.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Parse flags -------------------------------------------------------------
ADMIN_EMAIL="" PRODUCER_EMAIL="" CONSUMER_EMAIL=""
usage() {
  cat >&2 <<USAGE
Usage: $0 --admin <email> --producer <email> --consumer <email>

  --admin     <email>   Added as an Admin to the Customer Team AND the Marketing team.
  --producer  <email>   Added to the Customer Team with role "Data Producer".
  --consumer  <email>   Added to the Marketing team with role "Data Consumer".

All three are required.
USAGE
  exit 1
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --admin)    ADMIN_EMAIL="${2:-}"; shift 2;;
    --producer) PRODUCER_EMAIL="${2:-}"; shift 2;;
    --consumer) CONSUMER_EMAIL="${2:-}"; shift 2;;
    -h|--help)  usage;;
    *) echo "Unknown argument: $1" >&2; usage;;
  esac
done
[[ -n "$ADMIN_EMAIL" && -n "$PRODUCER_EMAIL" && -n "$CONSUMER_EMAIL" ]] || {
  echo "ERROR: --admin, --producer and --consumer are all required." >&2; usage; }

# --- Environment / helpers ---------------------------------------------------
# Source once: mints TOKEN, exports BASE_URL/OWNER_EMAIL, loads state. The 01..07
# subprocesses inherit these exports (token is minted once, not seven times).
source "$SCRIPT_DIR/00_env.sh"

# Marketing naming (override via env if desired).
export MARKETING_DOMAIN_NAME="${MARKETING_DOMAIN_NAME:-Bricks&Co Marketing}"
export MARKETING_TEAM_NAME="${MARKETING_TEAM_NAME:-Bricks&Co Marketing}"

# ensure_member TEAM_ID EMAIL ROLE — idempotent add-or-update of a team member.
ensure_member() {
  local team_id="$1" email="$2" role="$3" members mid cur
  members="$(api_get "/api/teams/$team_id/members")"
  mid="$(jq -r --arg e "$email" \
    'map(select((.member_identifier // .email // "") == $e)) | (.[0].id // empty)' <<<"$members")"
  if [[ -z "$mid" ]]; then
    api_post "/api/teams/$team_id/members" "$(jq -n --arg e "$email" --arg r "$role" \
      '{member_type:"user", member_identifier:$e, app_role_override:$r}')" >/dev/null
    echo "    added $email as $role"
    return 0
  fi
  cur="$(jq -r --arg e "$email" \
    'map(select((.member_identifier // .email // "") == $e)) | (.[0].app_role_override // "")' <<<"$members")"
  if [[ "$cur" != "$role" ]]; then
    api_put "/api/teams/$team_id/members/$mid" "$(jq -n --arg r "$role" '{app_role_override:$r}')" >/dev/null
    echo "    updated $email role: '${cur:-<none>}' -> '$role'"
  else
    echo "    $email already present as $role"
  fi
}

# ensure_domain NAME DESC — find-or-create a data domain; prints its id.
ensure_domain() {
  local name="$1" desc="$2" id
  id="$(find_id_by_name "$(api_get "/api/data-domains?limit=1000")" "$name")"
  if [[ -z "$id" ]]; then
    id="$(api_post "/api/data-domains" \
      "$(jq -n --arg n "$name" --arg d "$desc" '{name:$n, description:$d}')" | jq -r .id)"
    echo "    created domain '$name' ($id)" >&2
  else
    echo "    reusing domain '$name' ($id)" >&2
  fi
  printf '%s' "$id"
}

# ensure_team NAME DOMAIN_ID — find-or-create a team bound to a domain; prints its id.
# Enforces the domain binding even when reusing an existing team.
ensure_team() {
  local name="$1" dom="$2" id cur_primary
  id="$(find_id_by_name "$(api_get "/api/teams?limit=1000")" "$name")"
  if [[ -z "$id" ]]; then
    id="$(api_post "/api/teams" "$(jq -n --arg n "$name" --arg dom "$dom" \
      '{name:$n, title:$n,
        description:"Owns and operates the Marketing domain and its data products.",
        domain_ids:[$dom], primary_domain_id:$dom}')" | jq -r .id)"
    echo "    created team '$name' ($id)" >&2
  else
    echo "    reusing team '$name' ($id)" >&2
    cur_primary="$(api_get "/api/teams/$id" | jq -r '.primary_domain_id // empty')"
    if [[ "$cur_primary" != "$dom" ]]; then
      api_put "/api/teams/$id" "$(jq -n --arg dom "$dom" \
        '{domain_ids:[$dom], primary_domain_id:$dom}')" >/dev/null
      echo "    bound team '$name' to domain $dom" >&2
    fi
  fi
  printf '%s' "$id"
}

# =============================================================================
echo "==> [1/8] Running the Customer 360 guide (01..07)"
for s in 01_tags 02_domain 03_team 04_project 05_contract 06_product 07_tag_entities; do
  echo "--- $s.sh ---"
  "$SCRIPT_DIR/$s.sh"
done

# Refresh IDs written by the guide.
load_state
: "${DOMAIN_ID:?01..07 did not produce DOMAIN_ID}"
: "${TEAM_ID:?01..07 did not produce TEAM_ID}"
: "${PROJECT_ID:?01..07 did not produce PROJECT_ID}"

echo "==> [2/8] Creating Marketing domain '$MARKETING_DOMAIN_NAME'"
MARKETING_DOMAIN_ID="$(ensure_domain "$MARKETING_DOMAIN_NAME" \
  "Bricks&Co Marketing — campaigns, segments, and audience activation for customer engagement.")"
save_state MARKETING_DOMAIN_ID "$MARKETING_DOMAIN_ID"

echo "==> [3/8] Adding members to Customer Team ($TEAM_ID)"
ensure_member "$TEAM_ID" "$ADMIN_EMAIL"    "Admin"
ensure_member "$TEAM_ID" "$PRODUCER_EMAIL" "Data Producer"

echo "==> [4/8] Creating Marketing team '$MARKETING_TEAM_NAME'"
MARKETING_TEAM_ID="$(ensure_team "$MARKETING_TEAM_NAME" "$MARKETING_DOMAIN_ID")"
save_state MARKETING_TEAM_ID "$MARKETING_TEAM_ID"

echo "==> [5/8] Adding members to Marketing team ($MARKETING_TEAM_ID)"
ensure_member "$MARKETING_TEAM_ID" "$ADMIN_EMAIL"    "Admin"
ensure_member "$MARKETING_TEAM_ID" "$CONSUMER_EMAIL" "Data Consumer"

echo "==> [6/8] Promoting Customer 360 Project to a TEAM project"
api_put "/api/projects/$PROJECT_ID" '{"project_type":"TEAM"}' >/dev/null
echo "    project_type set to TEAM"

echo "==> [7/8] Assigning Customer Team to the project"
ASSIGNED="$(api_get "/api/projects/$PROJECT_ID/teams")"
if jq -e --arg t "$TEAM_ID" 'any(.[]; (.id // "") == $t)' <<<"$ASSIGNED" >/dev/null 2>&1; then
  echo "    Customer Team already assigned"
else
  api_post "/api/projects/$PROJECT_ID/teams" "$(jq -n --arg t "$TEAM_ID" '{team_id:$t}')" >/dev/null
  echo "    assigned Customer Team ($TEAM_ID)"
fi

echo "==> [8/8] Removing all tags from the Customer Core domain ($DOMAIN_ID)"
api_post "/api/entities/data_domain/$DOMAIN_ID/tags:set" '[]' >/dev/null
echo "    Customer Core domain tags cleared"

cat <<SUMMARY

==> Onboarding complete.
    Customer Core domain : $DOMAIN_ID (tags removed)
    Customer Team        : $TEAM_ID   (+admin=$ADMIN_EMAIL, +Data Producer=$PRODUCER_EMAIL)
    Customer 360 Project : $PROJECT_ID (type=TEAM, Customer Team assigned)
    Marketing domain     : $MARKETING_DOMAIN_ID
    Marketing team       : $MARKETING_TEAM_ID (+admin=$ADMIN_EMAIL, +Data Consumer=$CONSUMER_EMAIL)
SUMMARY
