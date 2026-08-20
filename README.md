# Bricks&Co — Customer 360 on Ontos (guide project)

This repo accompanies the **"Building a Data Product in Ontos"** user guide. It contains
everything to reproduce the Bricks&Co Customer 360 story end to end:

1. **`scripts/`** — idempotent CURL scripts that build the full governance graph in Ontos
   via the REST API: tag namespace + tags → Customer Core domain → Customer Team → Customer
   360 Project → **ODCS v3.1.0** data contract → **ODPS v1.0.0** data product → entity tagging.
2. **Databricks Asset Bundle** (`databricks.yml`, `resources/`, `src/`) — a serverless job that
   materializes the physical `${catalog}.${schema}.${table}` Delta table promised by the data
   product's output port, using synthetic data (PySpark + Faker), and applies Unity Catalog tags
   that mirror the Ontos governance tags.

## Prerequisites

- `curl`, `jq`, and the Databricks CLI (`databricks`) on your PATH.
- A Databricks CLI profile authenticated to the workspace hosting Ontos (default: `ontos`).
  ```bash
  databricks auth login -p ontos
  ```
- Access to the Ontos app with `READ_WRITE` on projects/teams/tags/contracts/products
  (creating the tag namespace needs `tags` `ADMIN`).

## Part 1 — Build the Ontos graph (CURL)

### Recommended: one-command onboarding (`10_onboard.sh`)

The fastest way to stand up the whole graph is the onboarding orchestrator. It runs the
entire guide (`01`..`07`) end to end in one shot and layers a small multi-team org
structure on top, parameterized by three users:

```bash
cd scripts
./10_onboard.sh \
  --admin    you@company.com \
  --producer producer@company.com \
  --consumer consumer@company.com
```

All three flags are **required**:

| Flag | Effect |
|------|--------|
| `--admin <email>` | Added as **Admin** to **both** the Customer Team and the Marketing team |
| `--producer <email>` | Added to the **Customer Team** with role **Data Producer** |
| `--consumer <email>` | Added to the **Marketing team** with role **Data Consumer** |

**What it does, in order:**

1. Runs `01_tags` → `07_tag_entities` (tags → Customer Core domain → Customer Team →
   Customer 360 Project → ODCS contract → ODPS product → entity tagging). The auth token
   is minted **once** and shared across all steps.
2. Creates the **"Bricks&Co Marketing"** data domain.
3. Creates the **"Bricks&Co Marketing"** team, bound to that domain.
4. Assigns the three users to their roles (see table above).
5. Promotes the **Customer 360 Project** to a `TEAM` project and assigns the Customer Team to it.
6. **Removes all tags from the Customer Core domain.**

The orchestrator is **idempotent** and safe to re-run. Because `01`..`07` recreate
resources by name, it also doubles as the **rebuild path after `99_cleanup.sh`**.

Override the Marketing names via environment variables if desired:
```bash
MARKETING_DOMAIN_NAME="Acme Marketing" MARKETING_TEAM_NAME="Acme Marketing" \
  ./10_onboard.sh --admin ... --producer ... --consumer ...
```

`10_onboard.sh` does **not** run `08_verify.sh` or `09_upload_docs.sh` — run those as
follow-ups (see below).

### Follow-ups

```bash
./08_verify.sh        # read back and summarize the whole graph
./09_upload_docs.sh   # attach the contract docs (Markdown + PDF from ../assets) to the data contract
```

`09_upload_docs.sh` requires `CONTRACT_ID` in `scripts/.ontos_state.env`, which onboarding
produces (via `05_contract.sh`).

### Manual / step-by-step (advanced)

To run the base guide without the extra Marketing org structure, invoke the scripts
individually:

```bash
cd scripts
./01_tags.sh        # tag namespace + controlled vocabulary
./02_domain.sh      # Customer Core domain
./03_team.sh        # Customer Team + owner member
./04_project.sh     # Customer 360 Project
./05_contract.sh    # ODCS v3.1.0 data contract
./06_product.sh     # ODPS v1.0.0 data product (output port -> contract)
./07_tag_entities.sh# assert the tag set across the graph
./08_verify.sh      # read back and summarize everything
```

Every script is **idempotent** — re-running reuses what exists instead of duplicating.
Created IDs are cached in `scripts/.ontos_state.env` and shared between steps.

Override any default via environment variables, e.g.:
```bash
BASE_URL=https://ontos-xxxx.aws.databricksapps.com DATABRICKS_PROFILE=ontos ./01_tags.sh
```

### Teardown

Optional teardown (reverse order):
```bash
CONFIRM=yes ./99_cleanup.sh
```

Re-run `10_onboard.sh` afterward to rebuild everything.

## Part 2 — Materialize the dataset (Databricks Asset Bundle)

The bundle's table target (`${catalog}.${schema}.${table}`) matches the data product's output
port `assetIdentifier` (`bricks_co.customer_360.customer_360_profile`).

```bash
databricks bundle validate -t dev
databricks bundle deploy   -t dev
databricks bundle run customer_360_synthetic_dataset -t dev
```

Variables (override with `--var` or per-target in `databricks.yml`):

| Variable | Default | Meaning |
|----------|---------|---------|
| `catalog` | `bricks_co` | UC catalog (must match the Ontos output port) |
| `schema` | `customer_360` | UC schema |
| `table` | `customer_360_profile` | Gold table name |
| `num_rows` | `5000` | Synthetic customers to generate |

> The job runs on **serverless** compute. It runs `CREATE CATALOG IF NOT EXISTS`, so the
> principal needs privileges to create the catalog (or point `catalog` at one you can write to).

## Tag parity (Ontos ⇄ Unity Catalog)

| Ontos tag (`bricksco/…`) | UC table tag | Applied where |
|--------------------------|--------------|----------------|
| `domain=customer` | `domain=customer` | table + job |
| `data-tier=gold` | `data-tier=gold` | table + job |
| `data-classification=restricted` | `data-classification=restricted` | table + job |
| `pii=present` | `pii=present` | table + PII columns |
| `lifecycle-status=active` | `lifecycle-status=active` | table + job |
| — | `source=ontos`, `data_product=customer-360-profile` | provenance |

## How the pieces line up

```
Ontos: Domain → Team → Project → Contract (ODCS v3.1.0) → Product (ODPS v1.0.0)
                                     │                          │ outputPort.assetIdentifier
                                     │ schema columns           ▼
                                     └────────────►  bricks_co.customer_360.customer_360_profile
                                                     (Delta table created by this bundle)
```
