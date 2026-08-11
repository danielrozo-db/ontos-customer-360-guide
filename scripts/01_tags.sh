#!/usr/bin/env bash
# =============================================================================
# 01_tags.sh — Create the Bricks&Co governance tag vocabulary
# =============================================================================
# A tag *namespace* groups related tags (like a folder). Within it we define a
# small controlled vocabulary the Customer team will apply to every asset:
#   domain, data-tier, data-classification, pii, lifecycle-status
# Each tag can declare `possible_values` so downstream users pick from a list.
# =============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"

echo "==> Ensuring tag namespace '$TAG_NAMESPACE'"
NS_LIST="$(api_get "/api/tags/namespaces")"
NS_ID="$(jq -r --arg n "$TAG_NAMESPACE" 'map(select(.name==$n)) | (.[0].id // empty)' <<<"$NS_LIST")"
if [[ -z "$NS_ID" ]]; then
  NS_ID="$(api_post "/api/tags/namespaces" "$(jq -n --arg n "$TAG_NAMESPACE" \
    '{name:$n, description:"Bricks&Co enterprise governance tag vocabulary"}')" | jq -r .id)"
  echo "    created namespace id=$NS_ID"
else
  echo "    reusing namespace id=$NS_ID"
fi
save_state NS_ID "$NS_ID"

# create_tag NAME DESCRIPTION "val1,val2,..."
create_tag() {
  local name="$1" desc="$2" values="$3"
  local existing
  existing="$(api_get "/api/tags?namespace_name=$TAG_NAMESPACE&name_contains=$name" \
    | jq -r --arg n "$name" 'map(select(.name==$n)) | (.[0].id // empty)')"
  if [[ -n "$existing" ]]; then
    echo "    reusing tag $TAG_NAMESPACE/$name ($existing)" >&2
    printf '%s' "$existing"; return 0
  fi
  local pv="[]"
  [[ -n "$values" ]] && pv="$(jq -Rc 'split(",")' <<<"$values")"
  api_post "/api/tags" "$(jq -n --arg n "$name" --arg ns "$TAG_NAMESPACE" \
     --arg d "$desc" --argjson pv "$pv" \
     '{name:$n, namespace_name:$ns, description:$d, possible_values:$pv, status:"active"}')" \
    | jq -r .id
}

echo "==> Ensuring tags in namespace '$TAG_NAMESPACE'"
TAG_DOMAIN_ID="$(create_tag domain "Business data domain the asset belongs to" "customer,order,product,finance")"
TAG_TIER_ID="$(create_tag data-tier "Medallion layer of the asset" "bronze,silver,gold")"
TAG_CLASS_ID="$(create_tag data-classification "Sensitivity classification" "public,internal,confidential,restricted")"
TAG_PII_ID="$(create_tag pii "Presence and handling of personal data" "none,masked,tokenized,present")"
TAG_LIFECYCLE_ID="$(create_tag lifecycle-status "Governance lifecycle state" "active,deprecated,retired")"

save_state TAG_DOMAIN_ID "$TAG_DOMAIN_ID"
save_state TAG_TIER_ID "$TAG_TIER_ID"
save_state TAG_CLASS_ID "$TAG_CLASS_ID"
save_state TAG_PII_ID "$TAG_PII_ID"
save_state TAG_LIFECYCLE_ID "$TAG_LIFECYCLE_ID"

echo "==> Tags ready:"
printf '    %s/%s\n' "$TAG_NAMESPACE" domain "$TAG_NAMESPACE" data-tier "$TAG_NAMESPACE" \
  data-classification "$TAG_NAMESPACE" pii "$TAG_NAMESPACE" lifecycle-status
