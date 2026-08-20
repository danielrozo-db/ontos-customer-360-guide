#!/usr/bin/env bash
# =============================================================================
# 05_contract.sh — Author the Customer 360 Profile data contract (ODCS v3.1.0)
# =============================================================================
# The data contract is the formal, versioned promise about the shape, quality,
# semantics, and SLAs of the customer_360_profile dataset. It is fully ODCS
# v3.1.0 compliant: schema + properties, quality rules, servers, team, roles,
# SLA properties, pricing, and support channels. It is linked to the Customer
# Team, the Customer 360 Project, and the Customer Core domain.
#
# NOTE: the output-port linkage in the data product references the *Ontos*
# contract UUID returned here (not the ODCS logical id) — we save it as
# CONTRACT_ID for 06_product.sh.
# =============================================================================
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"
load_state
: "${DOMAIN_ID:?run 02_domain.sh first}"
: "${TEAM_ID:?run 03_team.sh first}"
: "${PROJECT_ID:?run 04_project.sh first}"

echo "==> Ensuring data contract '$CONTRACT_NAME' in project"
C_LIST="$(api_get "/api/data-contracts?project_id=$PROJECT_ID&limit=1000")"
CONTRACT_ID="$(find_id_by_name "$C_LIST" "$CONTRACT_NAME")"

if [[ -z "$CONTRACT_ID" ]]; then
  BODY="$(jq -n \
    --arg name "$CONTRACT_NAME" \
    --arg team "$TEAM_ID" --arg project "$PROJECT_ID" --arg dom "$DOMAIN_ID" \
    --arg tenant "$ONTOS_TENANT" --arg owner "$OWNER_EMAIL" \
    --arg catalog "$UC_CATALOG" --arg schema "$UC_SCHEMA" --arg table "$UC_TABLE" '
  {
    name: $name,
    version: "1.0.0",
    status: "active",
    kind: "DataContract",
    apiVersion: "v3.1.0",
    owner_team_id: $team,
    project_id: $project,
    domainId: $dom,
    domainIds: [$dom],
    primaryDomainId: $dom,
    tenant: $tenant,
    dataProduct: "customer-360-profile",
    description: {
      purpose: "Authoritative, deduplicated 360-degree profile of every Bricks&Co customer: identity, contact details, consent, loyalty tier, and lifetime value.",
      usage: "Customer segmentation, CLV and churn modelling, marketing activation, and service-desk lookups. Join to order and interaction products on customer_id.",
      limitations: "Contains direct personal identifiers; restricted to consumers with an approved purpose. Refreshed daily; not intended for sub-daily operational use."
    },
    schema: [
      {
        name: "customer_360_profile",
        physicalName: $table,
        physicalType: "table",
        businessName: "Customer 360 Profile",
        description: "One row per customer with the golden profile record.",
        dataGranularityDescription: "One row per unique customer_id.",
        tags: [
          {tag_fqn: "bricksco/data-tier", assigned_value: "gold"},
          {tag_fqn: "bricksco/pii",       assigned_value: "present"}
        ],
        properties: [
          {name:"customer_id",       logicalType:"string",    physicalType:"STRING",    required:true, unique:true, primaryKey:true, primaryKeyPosition:1, classification:"internal",   businessName:"Customer ID", description:"Stable surrogate key for the customer.",
            quality:[{name:"customer_id_not_null", type:"library", rule:"nullValues", must_be:"0", dimension:"completeness", severity:"error", business_impact:"operational"}]},
          {name:"first_name",        logicalType:"string",    physicalType:"STRING",    required:true,  classification:"confidential", businessName:"First Name", description:"Customer given name."},
          {name:"last_name",         logicalType:"string",    physicalType:"STRING",    required:true,  classification:"confidential", businessName:"Last Name",  description:"Customer family name."},
          {name:"email",             logicalType:"string",    physicalType:"STRING",    required:true,  classification:"restricted",   businessName:"Email", description:"Primary email address.", pattern:"^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$",
            quality:[{name:"email_format", type:"library", rule:"invalidFormat", dimension:"conformity", severity:"warning", business_impact:"operational"}]},
          {name:"phone",             logicalType:"string",    physicalType:"STRING",    required:false, classification:"restricted",   businessName:"Phone", description:"Primary phone number in E.164 form."},
          {name:"address_line1",     logicalType:"string",    physicalType:"STRING",    required:false, classification:"confidential", businessName:"Address Line 1"},
          {name:"city",              logicalType:"string",    physicalType:"STRING",    required:false, classification:"internal",     businessName:"City"},
          {name:"state_province",    logicalType:"string",    physicalType:"STRING",    required:false, classification:"internal",     businessName:"State / Province"},
          {name:"postal_code",       logicalType:"string",    physicalType:"STRING",    required:false, classification:"internal",     businessName:"Postal Code"},
          {name:"country",           logicalType:"string",    physicalType:"STRING",    required:false, classification:"public",       businessName:"Country", description:"ISO 3166-1 alpha-2 code.", pattern:"^[A-Z]{2}$"},
          {name:"customer_since",    logicalType:"date",      physicalType:"DATE",      required:true,  classification:"internal",     businessName:"Customer Since", description:"Date the customer first registered."},
          {name:"loyalty_tier",      logicalType:"string",    physicalType:"STRING",    required:false, classification:"internal",     businessName:"Loyalty Tier", description:"One of: bronze, silver, gold, platinum."},
          {name:"lifetime_value",    logicalType:"number",    physicalType:"DECIMAL(12,2)", required:false, classification:"confidential", businessName:"Lifetime Value", description:"Modelled customer lifetime value in USD.", minimum:0},
          {name:"customer_status",   logicalType:"string",    physicalType:"STRING",    required:true,  classification:"internal",     businessName:"Customer Status", description:"One of: active, inactive, churned."},
          {name:"marketing_consent", logicalType:"boolean",   physicalType:"BOOLEAN",   required:true,  classification:"internal",     businessName:"Marketing Consent", description:"Whether the customer consented to marketing."},
          {name:"updated_at",        logicalType:"timestamp", physicalType:"TIMESTAMP", required:true,  classification:"internal",     businessName:"Updated At", description:"Last time the golden record changed."}
        ],
        quality: [
          {name:"row_count_positive", type:"library", rule:"rowCount", must_be_gt:"0", dimension:"completeness", severity:"error", business_impact:"operational", schedule:"0 6 * * *", scheduler:"cron"},
          {name:"customer_id_unique", type:"library", rule:"duplicateCount", must_be:"0", dimension:"uniqueness", severity:"error", business_impact:"operational"}
        ]
      }
    ],
    servers: [
      {server:"bricksco-prod", type:"databricks", environment:"prod",
       host:"<your-workspace>.cloud.databricks.com",
       catalog:$catalog, schema:$schema,
       description:"Unity Catalog Delta table backing the gold profile."}
    ],
    team: [
      {username:$owner, role:"Owner", description:"Product owner for Customer 360."},
      {username:"customer.steward@bricksco.com", role:"Data Steward", description:"Accountable for quality and consent."},
      {username:"customer.eng@bricksco.com", role:"Data Engineer"}
    ],
    roles: [
      {role:"customer_360_reader", access:"read",  firstLevelApprovers:"Customer Data Steward", secondLevelApprovers:"Customer Domain Owner"},
      {role:"customer_360_pii_reader", access:"read", description:"Access to unmasked PII columns.", firstLevelApprovers:"Privacy Office", secondLevelApprovers:"Customer Domain Owner"}
    ],
    slaProperties: [
      {property:"latency",            value:24, unit:"h", element:"customer_360_profile.updated_at", driver:"operational"},
      {property:"frequency",          value:1,  unit:"d", element:"customer_360_profile.updated_at", driver:"operational"},
      {property:"generalAvailability", value:"2026-08-15T06:00:00-05:00"},
      {property:"retention",          value:7,  unit:"y", element:"customer_360_profile.customer_since", driver:"regulatory"}
    ],
    price: {priceAmount: 0, priceCurrency: "USD", priceUnit: "record"},
    support: [
      {channel:"#customer-360-help", tool:"slack", scope:"interactive", url:"https://bricksco.slack.com/archives/C0CUST360", description:"Interactive support for consumers."},
      {channel:"customer-360-announce", tool:"email", scope:"announcements", url:"mailto:customer-360-announce@bricksco.com", description:"Release and deprecation announcements."}
    ],
    authoritativeDefinitions: [
      {type:"businessDefinition", url:"https://wiki.bricksco.com/domains/customer/customer-360-profile"},
      {type:"implementation",     url:"https://github.com/bricksco/customer-360/tree/main/pipelines"}
    ],
    customProperties: {
      "business-domain": "Customer",
      "chargeback-cost-center": "CC-CUST-360",
      "source-systems": "POS, eCommerce, CRM, Loyalty"
    },
    tags: [
      {tag_fqn: "bricksco/domain", assigned_value: "customer"},
      {tag_fqn: "bricksco/data-tier", assigned_value: "gold"},
      {tag_fqn: "bricksco/data-classification", assigned_value: "restricted"},
      {tag_fqn: "bricksco/pii", assigned_value: "present"},
      {tag_fqn: "bricksco/lifecycle-status", assigned_value: "active"}
    ]
  }')"
  CONTRACT_ID="$(api_post "/api/data-contracts" "$BODY" | jq -r .id)"
  echo "    created contract id=$CONTRACT_ID"
else
  echo "    reusing contract id=$CONTRACT_ID"
fi
save_state CONTRACT_ID "$CONTRACT_ID"
echo "==> Contract ready: $CONTRACT_NAME ($CONTRACT_ID)"
