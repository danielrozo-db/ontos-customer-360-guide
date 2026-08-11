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

Optional teardown (reverse order):
```bash
CONFIRM=yes ./99_cleanup.sh
```

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
