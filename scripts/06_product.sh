#!/usr/bin/env bash
# =============================================================================
# 06_product.sh — Publish the Customer 360 Profile data product (ODPS v1.0.0)
# =============================================================================
# The data product wraps the contract into a consumable, discoverable asset. Its
# single output port promises the gold customer_360_profile table and is backed
# by the ODCS contract from 05_contract.sh (contractId = the Ontos contract UUID).
# It also carries management ports (discovery/observability), support channels,
# an ODPS team block, and links to the Customer Team / Project / domain.
# =============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"
load_state
: "${DOMAIN_ID:?run 02_domain.sh first}"
: "${TEAM_ID:?run 03_team.sh first}"
: "${PROJECT_ID:?run 04_project.sh first}"
: "${CONTRACT_ID:?run 05_contract.sh first}"

echo "==> Ensuring data product '$PRODUCT_NAME' in project"
P_LIST="$(api_get "/api/data-products?limit=1000")"
PRODUCT_ID="$(jq -r --arg n "$PRODUCT_NAME" --arg proj "$PROJECT_ID" \
  'map(select(.name==$n and (.project_id==$proj or .project_id==null))) | (.[0].id // empty)' <<<"$P_LIST")"

if [[ -z "$PRODUCT_ID" ]]; then
  BODY="$(jq -n \
    --arg name "$PRODUCT_NAME" --arg contract "$CONTRACT_ID" \
    --arg team "$TEAM_ID" --arg project "$PROJECT_ID" --arg dom "$DOMAIN_ID" \
    --arg tenant "$ONTOS_TENANT" --arg owner "$OWNER_EMAIL" \
    --arg catalog "$UC_CATALOG" --arg schema "$UC_SCHEMA" --arg table "$UC_TABLE" '
  {
    apiVersion: "v1.0.0",
    kind: "DataProduct",
    id: "bricksco-customer-360-profile-dp-001",
    version: "1.0.0",
    status: "draft",
    name: $name,
    tenant: $tenant,
    domain_ids: [$dom],
    primary_domain_id: $dom,
    owner_team_id: $team,
    project_id: $project,
    description: {
      purpose: "A trustworthy, governed 360-degree view of every Bricks&Co customer for analytics, marketing activation, and service.",
      usage: "Subscribe to the output port and read the gold customer_360_profile table. Access to unmasked PII requires the customer_360_pii_reader role.",
      limitations: "Daily refresh; PII columns are governed. Not for sub-daily operational lookups."
    },
    outputPorts: [
      {
        name: "customer-360-profile",
        version: "1.0.0",
        description: "Gold Delta table with one golden record per customer.",
        type: "Table",
        contractId: $contract,
        assetType: "table",
        assetIdentifier: ($catalog + "." + $schema + "." + $table),
        status: "active",
        containsPii: true,
        autoApprove: false,
        server: {database: $catalog, schema: $schema, table: $table},
        tags: ["gold", "customer"],
        customProperties: [
          {property: "refreshSchedule", value: "0 6 * * *"},
          {property: "grain", value: "one row per customer_id"}
        ]
      }
    ],
    managementPorts: [
      {name:"discovery",     content:"discoverability", type:"rest", url:"https://api.bricksco.com/products/customer-360/discovery", description:"Catalog and metadata discovery."},
      {name:"observability", content:"observability",   type:"rest", url:"https://api.bricksco.com/products/customer-360/health",    description:"Freshness, volume, and quality metrics."}
    ],
    support: [
      {channel:"#customer-360-help", url:"https://bricksco.slack.com/archives/C0CUST360", tool:"slack", scope:"interactive", description:"Consumer support."},
      {channel:"customer-360-announce", url:"mailto:customer-360-announce@bricksco.com", tool:"email", scope:"announcements", description:"Announcements."}
    ],
    team: {
      name: "Bricks&Co Customer Team",
      description: "Owns and operates the Customer 360 product.",
      members: [
        {username:$owner, name:"Product Owner", role:"owner", dateIn:"2026-08-01"},
        {username:"customer.steward@bricksco.com", name:"Customer Steward", role:"data steward", dateIn:"2026-08-01"}
      ]
    },
    authoritativeDefinitions: [
      {type:"businessDefinition", url:"https://wiki.bricksco.com/domains/customer/customer-360"}
    ],
    customProperties: [
      {property:"productType", value:"consumer-aligned", description:"Position in the data product value chain."},
      {property:"cost-center", value:"CC-CUST-360"}
    ],
    tags: [
      {tag_fqn:"bricksco/domain", assigned_value:"customer"},
      {tag_fqn:"bricksco/data-tier", assigned_value:"gold"},
      {tag_fqn:"bricksco/data-classification", assigned_value:"restricted"},
      {tag_fqn:"bricksco/pii", assigned_value:"present"},
      {tag_fqn:"bricksco/lifecycle-status", assigned_value:"active"}
    ]
  }')"
  PRODUCT_ID="$(api_post "/api/data-products" "$BODY" | jq -r .id)"
  echo "    created product id=$PRODUCT_ID"
else
  echo "    reusing product id=$PRODUCT_ID"
fi
save_state PRODUCT_ID "$PRODUCT_ID"
echo "==> Data product ready: $PRODUCT_NAME ($PRODUCT_ID)"
