# Data Contract — Customer 360 Profile

*Open Data Contract Standard (ODCS) `v3.1.0` · Generated from the live Ontos contract on 2026-08-14*

This document describes the **Customer 360 Profile** data contract as registered in Ontos: its identity and versioning, the governance context it lives in, its full schema definition, the data-quality rules attached to it, and the accountable team. Field values reflect the contract's authoritative state as returned by the Ontos API (`GET /api/data-contracts/{id}`).

---

## 1. Contract Identity & Versioning

| Attribute | Value |
|-----------|-------|
| Name | Customer 360 Profile |
| Contract ID (Ontos UUID) | `37fdde49-bd5b-4d2f-8985-ad6dc2155a04` |
| Version | `1.0.0` |
| Status | **active** |
| Kind | `DataContract` |
| API Version (ODCS) | `v3.1.0` |
| Tenant | `BricksAndCoInc` |
| Created | 2026-08-14 12:35:46 (+02:00) |
| Last Updated | 2026-08-14 13:10:04 (+02:00) |
| Publication Scope | `none` (not yet published) |

---

## 2. Governance Context

The contract is bound into the Bricks&Co Customer governance hierarchy — a domain owned by a team, delivered within a project.

| Relationship | Name | ID |
|--------------|------|----|
| Domain | Bricks&Co Customer Core | `162711ff-c517-4975-bb4c-7aa5a8531cc4` |
| Owning Team | Bricks&Co Customer Team | `73671e16-f539-4f04-a431-7cf9b69e56d2` |
| Project | Bricks&Co Customer 360 Project | `74ec59e7-e66f-4b5b-b01f-6d3816dd348f` |

### Governance Tags

All tags are drawn from the `bricksco` enterprise governance namespace and are `active`.

| Tag (FQN) | Assigned Value |
|-----------|----------------|
| `bricksco/domain` | — |
| `bricksco/data-tier` | — |
| `bricksco/data-classification` | — |
| `bricksco/pii` | — |
| `bricksco/lifecycle-status` | — |

> The five governance tags are attached to the contract; assigned values are managed at the namespace's controlled-vocabulary level.

---

## 3. Purpose, Usage & Limitations

**Purpose**
: Authoritative, deduplicated 360-degree profile of every Bricks&Co customer: identity, contact details, consent, loyalty tier, and lifetime value.

**Usage**
: Customer segmentation, CLV and churn modelling, marketing activation, and service-desk lookups. Join to order and interaction products on `customer_id`.

**Limitations**
: Contains direct personal identifiers; restricted to consumers with an approved purpose. Refreshed daily; not intended for sub-daily operational use.

---

## 4. Schema Definition

**Schema object:** `customer_360_profile` &nbsp;·&nbsp; **Business name:** Customer 360 Profile &nbsp;·&nbsp; **Physical type:** `table` &nbsp;·&nbsp; **Property count:** 16

> One row per customer with the golden profile record.

### 4.1 Properties

| # | Property | Business Name | Logical Type | Physical Type | Req. | Unique | PK | Classification | Constraints |
|---|----------|---------------|--------------|---------------|:----:|:------:|:--:|----------------|-------------|
| 1 | `customer_id` | Customer ID | string | STRING | ✓ | ✓ | ✓ (pos 1) | internal | Stable surrogate key |
| 2 | `first_name` | First Name | string | STRING | ✓ | | | confidential | — |
| 3 | `last_name` | Last Name | string | STRING | ✓ | | | confidential | — |
| 4 | `email` | Email | string | STRING | ✓ | | | restricted | pattern `^[^@\s]+@[^@\s]+\.[^@\s]+$` |
| 5 | `phone` | Phone | string | STRING | | | | restricted | E.164 form |
| 6 | `address_line1` | Address Line 1 | string | STRING | | | | confidential | — |
| 7 | `city` | City | string | STRING | | | | internal | — |
| 8 | `state_province` | State / Province | string | STRING | | | | internal | — |
| 9 | `postal_code` | Postal Code | string | STRING | | | | internal | — |
| 10 | `country` | Country | string | STRING | | | | public | pattern `^[A-Z]{2}$` (ISO 3166-1 α-2) |
| 11 | `customer_since` | Customer Since | date | DATE | ✓ | | | internal | Registration date |
| 12 | `loyalty_tier` | Loyalty Tier | string | STRING | | | | internal | bronze / silver / gold / platinum |
| 13 | `lifetime_value` | Lifetime Value | number | DECIMAL(12,2) | | | | confidential | minimum `0` (USD) |
| 14 | `customer_status` | Customer Status | string | STRING | ✓ | | | internal | active / inactive / churned |
| 15 | `marketing_consent` | Marketing Consent | boolean | BOOLEAN | ✓ | | | internal | Consent flag |
| 16 | `updated_at` | Updated At | timestamp | TIMESTAMP | ✓ | | | internal | Golden-record change time |

**Legend** — **Req.**: required · **PK**: primary key (with ordinal position).

### 4.2 Classification Summary

| Classification | Columns |
|----------------|---------|
| restricted | `email`, `phone` |
| confidential | `first_name`, `last_name`, `address_line1`, `lifetime_value` |
| internal | `customer_id`, `city`, `state_province`, `postal_code`, `customer_since`, `loyalty_tier`, `customer_status`, `marketing_consent`, `updated_at` |
| public | `country` |

---

## 5. Data Quality Rules

Two library-based quality rules are registered on the contract.

| Rule | Column | Type | Rule Kind | Dimension | Severity | Condition | Business Impact | Enabled |
|------|--------|------|-----------|-----------|----------|-----------|-----------------|:-------:|
| `customer_id_not_null` | `customer_id` | library | `nullValues` | completeness | error | must be `0` | operational | ✓ |
| `email_format` | `email` | library | `invalidFormat` | conformity | warning | valid format | operational | ✓ |

---

## 6. Accountable Team

| Username | Role | Description |
|----------|------|-------------|
| `unknown@dev.local` | Owner | Product owner for Customer 360. |
| `customer.steward@bricksco.com` | Data Steward | Accountable for quality and consent. |
| `customer.eng@bricksco.com` | Data Engineer | — |

---

## 7. Notes on Contract State

- **Status is `active`** and the contract is fully versioned at `1.0.0` under ODCS `v3.1.0`.
- The following ODCS blocks are **not currently populated** in the registered contract: `servers`, `slaProperties`, `price`, `support`, `roles`, and `authoritativeDefinitions`. Object-level quality assertions are surfaced through the two property-level rules in Section 5.
- Governance tags are attached but carry no per-assignment value; values are governed by the `bricksco` namespace vocabulary.
- The contract is referenced by the **Customer 360 Profile** data product's output port, which points at the physical asset `bricks_co.customer_360.customer_360_profile`.
