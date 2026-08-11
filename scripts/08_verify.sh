#!/usr/bin/env bash
# =============================================================================
# 08_verify.sh — Read back and summarize everything the guide created
# =============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"
load_state

echo "================ Bricks&Co Customer 360 — Ontos graph ================"
printf '%-16s %s\n' "Namespace:" "$TAG_NAMESPACE (${NS_ID:-?})"

echo; echo "Tags in namespace '$TAG_NAMESPACE':"
api_get "/api/tags?namespace_name=$TAG_NAMESPACE&limit=100" \
  | jq -r '.[] | "  - \(.fully_qualified_name)  values=\(.possible_values // [])"'

echo; echo "Domain:"
api_get "/api/data-domains/${DOMAIN_ID}" \
  | jq -r '"  \(.name) (\(.id))\n  tags: \([.tags[]?.fully_qualified_name] | join(", "))"'

echo; echo "Team:"
api_get "/api/teams/${TEAM_ID}" \
  | jq -r '"  \(.name) (\(.id))\n  members: \([.members[]?.member_identifier // .members[]?.email] | join(", "))"'

echo; echo "Project:"
api_get "/api/projects/${PROJECT_ID}" \
  | jq -r '"  \(.name) (\(.id))\n  owner_team: \(.owner_team_name // .owner_team_id)"'

echo; echo "Data contract (ODCS v3.1.0):"
api_get "/api/data-contracts/${CONTRACT_ID}" \
  | jq -r '"  \(.name) v\(.version) [\(.status)] (\(.id))\n  schema objects: \([.schema[]?.name] | join(", "))\n  columns: \([.schema[0].properties[]?.name] | join(", "))\n  tags: \([.tags[]?.fully_qualified_name] | join(", "))"'

echo; echo "Data product (ODPS v1.0.0):"
api_get "/api/data-products/${PRODUCT_ID}" \
  | jq -r '"  \(.name) v\(.version) [\(.status)] (\(.id))\n  output ports: \([.outputPorts[]? | "\(.name) -> \(.assetIdentifier) (contract \(.contractId))"] | join("; "))\n  tags: \([.tags[]?.fully_qualified_name // .tags[]?.tag_fqn] | join(", "))"'

echo "======================================================================"
echo "State file: $STATE_FILE"
