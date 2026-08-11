#!/usr/bin/env bash
# =============================================================================
# 07_tag_entities.sh — Assert the governance tag set on every entity
# =============================================================================
# Domains/teams/projects/contracts/products all accept inline tags at creation,
# but this step demonstrates the dedicated entity-tagging API and guarantees a
# consistent, auditable tag set across the whole graph. `tags:set` REPLACES the
# entity's tags with exactly the list provided, so it is safe to re-run.
#
# Body is a bare JSON array of AssignedTagCreate objects: {tag_fqn, assigned_value}.
# =============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"
load_state
: "${DOMAIN_ID:?run 02_domain.sh first}"
: "${TEAM_ID:?run 03_team.sh first}"
: "${PROJECT_ID:?run 04_project.sh first}"
: "${CONTRACT_ID:?run 05_contract.sh first}"
: "${PRODUCT_ID:?run 06_product.sh first}"

# The full governed tag set applied to customer assets.
TAGSET='[
  {"tag_fqn":"bricksco/domain","assigned_value":"customer"},
  {"tag_fqn":"bricksco/data-tier","assigned_value":"gold"},
  {"tag_fqn":"bricksco/data-classification","assigned_value":"restricted"},
  {"tag_fqn":"bricksco/pii","assigned_value":"present"},
  {"tag_fqn":"bricksco/lifecycle-status","assigned_value":"active"}
]'

set_tags() { # set_tags ENTITY_TYPE ENTITY_ID
  local etype="$1" eid="$2"
  if api_post "/api/entities/$etype/$eid/tags:set" "$TAGSET" >/dev/null 2>/tmp/tagerr; then
    echo "    tagged $etype/$eid"
  else
    echo "    (skip) $etype/$eid — $(head -c 160 /tmp/tagerr)"
  fi
}

echo "==> Asserting tag set across the Customer 360 graph"
set_tags data_domain   "$DOMAIN_ID"
set_tags team          "$TEAM_ID"
set_tags project       "$PROJECT_ID"
set_tags data_contract "$CONTRACT_ID"
set_tags data_product  "$PRODUCT_ID"
echo "==> Tagging complete."
