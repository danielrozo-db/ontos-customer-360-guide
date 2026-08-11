#!/usr/bin/env bash
# =============================================================================
# 02_domain.sh — Create the Customer Core data domain
# =============================================================================
# The domain is the top of the Customer org's governance hierarchy: it owns
# customer identity, master records, and overall customer state. Teams, projects,
# contracts, and products all hang off it. We tag it inline at creation time.
# =============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"

echo "==> Ensuring data domain '$DOMAIN_NAME'"
DOMAIN_LIST="$(api_get "/api/data-domains?limit=1000")"
DOMAIN_ID="$(find_id_by_name "$DOMAIN_LIST" "$DOMAIN_NAME")"

if [[ -z "$DOMAIN_ID" ]]; then
  BODY="$(jq -n --arg name "$DOMAIN_NAME" '
    {
      name: $name,
      description: "Bricks&Co Customer Core — the authoritative domain for customer identity, master records, consent, and overall customer state across all channels (stores, web, app).",
      tags: [
        {tag_fqn: "bricksco/domain",              assigned_value: "customer"},
        {tag_fqn: "bricksco/data-classification", assigned_value: "restricted"},
        {tag_fqn: "bricksco/lifecycle-status",    assigned_value: "active"}
      ]
    }')"
  DOMAIN_ID="$(api_post "/api/data-domains" "$BODY" | jq -r .id)"
  echo "    created domain id=$DOMAIN_ID"
else
  echo "    reusing domain id=$DOMAIN_ID"
fi
save_state DOMAIN_ID "$DOMAIN_ID"
echo "==> Domain ready: $DOMAIN_NAME ($DOMAIN_ID)"
