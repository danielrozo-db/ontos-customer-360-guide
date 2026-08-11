#!/usr/bin/env bash
# =============================================================================
# 04_project.sh — Create the Customer 360 Project
# =============================================================================
# A project is the collaboration space where the team delivers data contracts
# and products for the domain. It is owned by the Customer Team and scoped to
# the Customer Core domain.
# =============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"
load_state
: "${DOMAIN_ID:?run 02_domain.sh first}"
: "${TEAM_ID:?run 03_team.sh first}"

echo "==> Ensuring project '$PROJECT_NAME'"
PROJ_LIST="$(api_get "/api/projects?limit=1000")"
PROJECT_ID="$(find_id_by_name "$PROJ_LIST" "$PROJECT_NAME")"

if [[ -z "$PROJECT_ID" ]]; then
  BODY="$(jq -n --arg name "$PROJECT_NAME" --arg team "$TEAM_ID" --arg dom "$DOMAIN_ID" '
    {
      name: $name,
      title: "Bricks&Co Customer 360 Project",
      description: "Delivery workspace for the Customer 360 Profile data contract and data product.",
      owner_team_id: $team,
      domain_ids: [$dom],
      primary_domain_id: $dom,
      tags: [
        {tag_fqn: "bricksco/domain", assigned_value: "customer"},
        {tag_fqn: "bricksco/lifecycle-status", assigned_value: "active"}
      ]
    }')"
  PROJECT_ID="$(api_post "/api/projects" "$BODY" | jq -r .id)"
  echo "    created project id=$PROJECT_ID"
else
  echo "    reusing project id=$PROJECT_ID"
fi
save_state PROJECT_ID "$PROJECT_ID"
echo "==> Project ready: $PROJECT_NAME ($PROJECT_ID)"
