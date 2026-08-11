# Databricks notebook source
# MAGIC %md
# MAGIC # Bricks&Co — Customer 360 Profile synthetic dataset
# MAGIC
# MAGIC Materializes the physical table promised by the Ontos **Customer 360 Profile**
# MAGIC data product's output port. Column names/types match the ODCS v3.1.0 contract
# MAGIC (`05_contract.sh`). After writing the gold Delta table, it applies Unity Catalog
# MAGIC table + column tags that mirror the Ontos governance tags.

# COMMAND ----------
# MAGIC %pip install faker==30.8.2
# COMMAND ----------
dbutils.library.restartPython()

# COMMAND ----------
# Parameters (bound to bundle variables via the job's base_parameters)
dbutils.widgets.text("catalog", "bricks_co")
dbutils.widgets.text("schema", "customer_360")
dbutils.widgets.text("table", "customer_360_profile")
dbutils.widgets.text("num_rows", "5000")

CATALOG = dbutils.widgets.get("catalog")
SCHEMA = dbutils.widgets.get("schema")
TABLE = dbutils.widgets.get("table")
NUM_ROWS = int(dbutils.widgets.get("num_rows"))
FQN = f"{CATALOG}.{SCHEMA}.{TABLE}"
print(f"Target table: {FQN}  rows={NUM_ROWS}")

# COMMAND ----------
import random
from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP

from faker import Faker
from pyspark.sql.types import (
    StructType, StructField, StringType, DateType, TimestampType,
    BooleanType, DecimalType,
)

fake = Faker()
Faker.seed(42)
random.seed(42)

LOYALTY_TIERS = ["bronze", "silver", "gold", "platinum"]
STATUSES = ["active", "active", "active", "inactive", "churned"]  # weighted toward active


def make_row(i: int) -> dict:
    since = fake.date_between(start_date="-8y", end_date="today")
    ltv = Decimal(random.uniform(0, 25000)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    return {
        "customer_id": f"CUST-{i:08d}",
        "first_name": fake.first_name(),
        "last_name": fake.last_name(),
        "email": fake.unique.email(),
        "phone": fake.phone_number()[:20],
        "address_line1": fake.street_address(),
        "city": fake.city(),
        "state_province": fake.state_abbr(),
        "postal_code": fake.postcode(),
        "country": "US",
        "customer_since": since,
        "loyalty_tier": random.choice(LOYALTY_TIERS),
        "lifetime_value": ltv,
        "customer_status": random.choice(STATUSES),
        "marketing_consent": random.random() < 0.72,
        "updated_at": datetime.now(timezone.utc),
    }


rows = [make_row(i) for i in range(1, NUM_ROWS + 1)]

# Explicit schema matching the ODCS contract's logical/physical types.
spark_schema = StructType([
    StructField("customer_id", StringType(), False),
    StructField("first_name", StringType(), False),
    StructField("last_name", StringType(), False),
    StructField("email", StringType(), False),
    StructField("phone", StringType(), True),
    StructField("address_line1", StringType(), True),
    StructField("city", StringType(), True),
    StructField("state_province", StringType(), True),
    StructField("postal_code", StringType(), True),
    StructField("country", StringType(), True),
    StructField("customer_since", DateType(), False),
    StructField("loyalty_tier", StringType(), True),
    StructField("lifetime_value", DecimalType(12, 2), True),
    StructField("customer_status", StringType(), False),
    StructField("marketing_consent", BooleanType(), False),
    StructField("updated_at", TimestampType(), False),
])

df = spark.createDataFrame(rows, schema=spark_schema)
print(f"Generated {df.count()} rows")

# COMMAND ----------
# Ensure catalog/schema exist. Creating the catalog needs metastore privilege;
# when pointing at an existing catalog we tolerate a permission error here.
try:
    spark.sql(f"CREATE CATALOG IF NOT EXISTS {CATALOG}")
except Exception as e:
    print(f"Skipping CREATE CATALOG ({CATALOG} assumed to exist): {e}")
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOG}.{SCHEMA}")

(df.write
   .format("delta")
   .mode("overwrite")
   .option("overwriteSchema", "true")
   .saveAsTable(FQN))

spark.sql(
    f"COMMENT ON TABLE {FQN} IS "
    f"'Bricks&Co Customer 360 Profile — gold golden record. Backs the Ontos data product output port.'"
)
print(f"Wrote {FQN}")

# COMMAND ----------
# MAGIC %md
# MAGIC ## Apply Unity Catalog tags mirroring the Ontos governance vocabulary
# MAGIC Ontos tag  →  UC tag parity: `domain`, `data-tier`, `data-classification`, `pii`,
# MAGIC `lifecycle-status`, plus provenance (`source=ontos`, `data_product`).

# COMMAND ----------
# Some metastores enforce Unity Catalog *tag policies* that restrict the allowed
# values for certain governed tag keys (e.g. `source`). SET TAGS is atomic, so a
# single disallowed key fails the whole statement. We therefore apply each key
# individually and skip (with a log) any the workspace policy rejects, instead of
# failing the job. Adjust these to your workspace's approved tag vocabulary.
TABLE_TAGS = {
    "domain": "customer",
    "data-tier": "gold",
    "data-classification": "restricted",
    "pii": "present",
    "lifecycle-status": "active",
    "source": "ontos",                       # may be governed by a tag policy
    "data_product": "customer-360-profile",
}

def set_table_tag(key: str, value: str):
    try:
        spark.sql(f"ALTER TABLE {FQN} SET TAGS ('{key}' = '{value}')")
        print(f"  table tag {key}={value}")
    except Exception as e:
        msg = str(e).splitlines()[0]
        print(f"  (skipped table tag {key}={value}) {msg}")

def set_col_tag(col: str, key: str, value: str):
    try:
        spark.sql(f"ALTER TABLE {FQN} ALTER COLUMN {col} SET TAGS ('{key}' = '{value}')")
        print(f"  column tag {col}.{key}={value}")
    except Exception as e:
        msg = str(e).splitlines()[0]
        print(f"  (skipped column tag {col}.{key}={value}) {msg}")

print("Applying table tags:")
for k, v in TABLE_TAGS.items():
    set_table_tag(k, v)

print("Applying column tags:")
for col in ["first_name", "last_name", "email", "phone", "address_line1"]:
    set_col_tag(col, "pii", "present")
set_col_tag("customer_id", "data-classification", "internal")

print("Tagging step complete (governed keys skipped if rejected).")

# COMMAND ----------
display(spark.sql(f"SELECT * FROM {FQN} LIMIT 20"))
# COMMAND ----------
display(spark.sql(f"SHOW TAGS ON TABLE {FQN}")) if False else print("Done. Table:", FQN)
