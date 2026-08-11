#!/usr/bin/env bash
# =============================================================================
# 03_team.sh — Create the Customer Team and add its owner member
# =============================================================================
# The team is the group of people accountable for the Customer domain's data
# products. It is bound to the domain (domain_ids/primary_domain_id). We add the
# current user as an owner member — this matters because creating a contract or
# product inside a project requires project membership, which is derived from
# the owning team's members.
# =============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"
load_state
: "${DOMAIN_ID:?run 02_domain.sh first}"

echo "==> Ensuring team '$TEAM_NAME'"
TEAM_LIST="$(api_get "/api/teams?limit=1000")"
TEAM_ID="$(find_id_by_name "$TEAM_LIST" "$TEAM_NAME")"

if [[ -z "$TEAM_ID" ]]; then
  BODY="$(jq -n --arg name "$TEAM_NAME" --arg dom "$DOMAIN_ID" '
    {
      name: $name,
      title: "Bricks&Co Customer Team",
      description: "Owns and operates the Customer Core domain and its data products end to end.",
      domain_ids: [$dom],
      primary_domain_id: $dom,
      tags: [
        {tag_fqn: "bricksco/domain", assigned_value: "customer"},
        {tag_fqn: "bricksco/lifecycle-status", assigned_value: "active"}
      ]
    }')"
  TEAM_ID="$(api_post "/api/teams" "$BODY" | jq -r .id)"
  echo "    created team id=$TEAM_ID"
else
  echo "    reusing team id=$TEAM_ID"
fi
save_state TEAM_ID "$TEAM_ID"

echo "==> Ensuring owner member '$OWNER_EMAIL' on team"
MEMBERS="$(api_get "/api/teams/$TEAM_ID/members")"
if jq -e --arg e "$OWNER_EMAIL" 'any(.[]; (.member_identifier // .email // "") == $e)' <<<"$MEMBERS" >/dev/null 2>&1; then
  echo "    member already present"
else
  api_post "/api/teams/$TEAM_ID/members" "$(jq -n --arg id "$OWNER_EMAIL" \
    '{member_type:"user", member_identifier:$id, app_role_override:"Admin"}')" >/dev/null
  echo "    added $OWNER_EMAIL as owner"
fi
echo "==> Team ready: $TEAM_NAME ($TEAM_ID)"
