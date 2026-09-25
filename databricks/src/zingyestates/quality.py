"""Declarative data-quality rules.

Each rule is a Spark SQL boolean expression that a valid row must satisfy.
A NULL result counts as a failure. Rows failing any rule go to the quarantine
zone with the list of failed rule names in `_dq_failures`.
"""

from __future__ import annotations

from dataclasses import dataclass

from pyspark.sql import DataFrame, Window
from pyspark.sql import functions as F


@dataclass(frozen=True)
class Rule:
    name: str
    condition: str


PROPERTY_TYPES = "('SINGLE_FAMILY','CONDO','TOWNHOUSE','MULTI_FAMILY','COMMERCIAL','LAND')"
LISTING_STATUSES = "('ACTIVE','PENDING','SOLD','WITHDRAWN','EXPIRED')"

RULES: dict[str, list[Rule]] = {
    "properties": [
        Rule("property_id_present", "property_id IS NOT NULL AND property_id <> ''"),
        Rule("square_feet_positive", "square_feet > 0"),
        Rule("bedrooms_in_range", "bedrooms BETWEEN 0 AND 50"),
        Rule("state_is_iso_code", "state RLIKE '^[A-Z]{2}$'"),
        Rule("property_type_known", f"property_type IN {PROPERTY_TYPES}"),
        Rule("year_built_plausible", "year_built IS NULL OR year_built BETWEEN 1700 AND year(current_date()) + 2"),
    ],
    "agents": [
        Rule("agent_id_present", "agent_id IS NOT NULL AND agent_id <> ''"),
        Rule("email_valid", "email RLIKE '^[^@\\\\s]+@[^@\\\\s]+\\\\.[^@\\\\s]+$'"),
        Rule("license_present", "license_number IS NOT NULL"),
    ],
    "sales_transactions": [
        Rule("transaction_id_present", "transaction_id IS NOT NULL"),
        Rule("property_id_present", "property_id IS NOT NULL"),
        Rule("sale_price_positive", "sale_price > 0"),
        Rule("closing_after_sale", "closing_date IS NULL OR closing_date >= sale_date"),
    ],
    "leases": [
        Rule("lease_id_present", "lease_id IS NOT NULL"),
        Rule("property_id_present", "property_id IS NOT NULL"),
        Rule("rent_positive", "monthly_rent > 0"),
        Rule("lease_end_after_start", "lease_end > lease_start"),
    ],
    "listings": [
        Rule("listing_id_present", "listing_id IS NOT NULL"),
        Rule("list_price_positive", "list_price > 0"),
        Rule("status_known", f"status IN {LISTING_STATUSES}"),
    ],
}


def apply_rules(df: DataFrame, rules: list[Rule]) -> tuple[DataFrame, DataFrame]:
    """Split df into (valid, rejected). Rejected rows carry `_dq_failures: array<string>`."""
    checks = [F.when(F.coalesce(F.expr(r.condition), F.lit(False)), F.lit(None)).otherwise(F.lit(r.name)) for r in rules]
    flagged = df.withColumn("_dq_failures", F.filter(F.array(*checks), lambda x: x.isNotNull()))
    valid = flagged.filter(F.size("_dq_failures") == 0).drop("_dq_failures")
    rejected = flagged.filter(F.size("_dq_failures") > 0)
    return valid, rejected


def latest_per_key(df: DataFrame, key: str, order_by: str = "updated_at") -> DataFrame:
    """Keep the most recent version of each business key."""
    w = Window.partitionBy(key).orderBy(F.col(order_by).desc_nulls_last(), F.col("_ingested_at").desc())
    return df.withColumn("_rn", F.row_number().over(w)).filter("_rn = 1").drop("_rn")
