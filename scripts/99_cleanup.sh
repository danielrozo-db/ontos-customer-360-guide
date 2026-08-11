#!/usr/bin/env bash
# =============================================================================
# 99_cleanup.sh — Delete everything the guide created (reverse dependency order)
# =============================================================================
# OPTIONAL teardown. Deletes product -> contract -> project -> team -> domain,
# then the tags and namespace. Safe to run repeatedly; missing resources are
# ignored. Run only if you want to leave the workspace clean.
#
#   CONFIRM=yes ./99_cleanup.sh
# =============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"
load_state

if [[ "${CONFIRM:-}" != "yes" ]]; then
  echo "This will DELETE the Bricks&Co Customer 360 resources created by this guide."
  echo "Re-run with:  CONFIRM=yes $0"
  exit 1
fi

del() { # del PATH LABEL
  if api_delete "$1" >/dev/null 2>/tmp/delerr; then
    echo "    deleted $2"
  else
    echo "    (skip) $2 — $(head -c 160 /tmp/delerr)"
  fi
}

echo "==> Deleting Customer 360 graph (reverse order)"
[[ -n "${PRODUCT_ID:-}"  ]] && del "/api/data-products/$PRODUCT_ID"   "product $PRODUCT_ID"
[[ -n "${CONTRACT_ID:-}" ]] && del "/api/data-contracts/$CONTRACT_ID" "contract $CONTRACT_ID"
[[ -n "${PROJECT_ID:-}"  ]] && del "/api/projects/$PROJECT_ID"        "project $PROJECT_ID"
[[ -n "${TEAM_ID:-}"     ]] && del "/api/teams/$TEAM_ID"              "team $TEAM_ID"
[[ -n "${DOMAIN_ID:-}"   ]] && del "/api/data-domains/$DOMAIN_ID"     "domain $DOMAIN_ID"

echo "==> Deleting tags"
for v in TAG_DOMAIN_ID TAG_TIER_ID TAG_CLASS_ID TAG_PII_ID TAG_LIFECYCLE_ID; do
  id="${!v:-}"; [[ -n "$id" ]] && del "/api/tags/$id" "tag $v=$id"
done

# The tag namespace is NOT deleted by default — it may be shared with other
# assets. Opt in explicitly:  DELETE_NAMESPACE=yes CONFIRM=yes ./99_cleanup.sh
if [[ "${DELETE_NAMESPACE:-}" == "yes" && -n "${NS_ID:-}" ]]; then
  del "/api/tags/namespaces/$NS_ID" "namespace $NS_ID"
fi

echo "==> Ontos cleanup complete. Removing local state file."
rm -f "$STATE_FILE"

cat <<'REMINDER'

NOTE: this script only removes resources in Ontos. To remove the Databricks side:
  1. Destroy the bundle (deletes the job):   databricks bundle destroy -t dev
  2. Drop the generated data (bundle destroy does NOT delete data):
       DROP TABLE  IF EXISTS bricks_co.customer_360.customer_360_profile;
       DROP SCHEMA IF EXISTS bricks_co.customer_360;
       -- DROP CATALOG IF EXISTS bricks_co;   -- only if this guide created it
REMINDER
