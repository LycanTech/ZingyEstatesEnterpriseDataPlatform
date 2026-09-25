"""Silver -> Gold: star schema for reporting plus Synapse export snapshots."""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F

from zingyestates.config import PlatformConfig
from zingyestates.entities import ENTITIES
from zingyestates.metrics import Metrics

log = logging.getLogger(__name__)

FRESHNESS_THRESHOLD_MINUTES = 30


def _date_key(col: str) -> F.Column:
    return F.date_format(F.col(col), "yyyyMMdd").cast("int")


def build_tables(silver: dict[str, DataFrame]) -> dict[str, DataFrame]:
    properties, agents = silver["properties"], silver["agents"]
    sales, leases, listings = silver["sales_transactions"], silver["leases"], silver["listings"]

    dim_property = properties.select(
        F.xxhash64("property_id").alias("property_sk"),
        "property_id",
        "address_line",
        "city",
        "state",
        "postal_code",
        "property_type",
        "bedrooms",
        "bathrooms",
        "square_feet",
        "year_built",
        "updated_at",
    )

    dim_agent = agents.select(
        F.xxhash64("agent_id").alias("agent_sk"),
        "agent_id",
        F.concat_ws(" ", "first_name", "last_name").alias("full_name"),
        "email",
        "office",
        "license_number",
        "hired_date",
        "updated_at",
    )

    fact_sales = sales.join(properties.select("property_id", "square_feet"), "property_id", "left").select(
        "transaction_id",
        "property_id",
        "agent_id",
        _date_key("sale_date").alias("sale_date_key"),
        "sale_date",
        "closing_date",
        "financing_type",
        "sale_price",
        F.round(F.col("sale_price") / F.col("square_feet"), 2).cast("decimal(18,2)").alias("price_per_sqft"),
        F.datediff("closing_date", "sale_date").alias("days_to_close"),
    )

    fact_leases = leases.select(
        "lease_id",
        "property_id",
        "agent_id",
        _date_key("lease_start").alias("lease_start_date_key"),
        "lease_start",
        "lease_end",
        "monthly_rent",
        F.round(F.months_between("lease_end", "lease_start")).cast("int").alias("lease_term_months"),
        (F.col("monthly_rent") * 12).cast("decimal(18,2)").alias("annualized_rent"),
    )

    fact_listings = listings.select(
        "listing_id",
        "property_id",
        "agent_id",
        _date_key("listed_at").alias("listed_date_key"),
        "listed_at",
        "status",
        "list_price",
        F.datediff(F.current_date(), F.to_date("listed_at")).alias("days_on_market"),
    )

    all_dates = (
        fact_sales.select(F.col("sale_date").alias("d"))
        .union(fact_leases.select(F.col("lease_start").alias("d")))
        .union(fact_listings.select(F.to_date("listed_at").alias("d")))
        .agg(F.min("d").alias("lo"), F.max("d").alias("hi"))
    )
    dim_date = (
        all_dates.where("lo IS NOT NULL")
        .select(F.explode(F.sequence(F.trunc("lo", "year"), F.last_day(F.add_months(F.trunc("hi", "year"), 11)))).alias("date"))
        .select(
            _date_key("date").alias("date_key"),
            "date",
            F.year("date").alias("year"),
            F.quarter("date").alias("quarter"),
            F.month("date").alias("month"),
            F.date_format("date", "MMMM").alias("month_name"),
            F.dayofweek("date").alias("day_of_week"),
            F.dayofweek("date").isin(1, 7).alias("is_weekend"),
        )
    )

    agg_market_monthly = (
        fact_sales.join(dim_property.select("property_id", "city", "state"), "property_id")
        .groupBy("city", "state", F.trunc("sale_date", "month").alias("month"))
        .agg(
            F.count("*").alias("sales_count"),
            F.sum("sale_price").cast("decimal(18,2)").alias("total_volume"),
            F.percentile_approx("sale_price", 0.5).cast("decimal(18,2)").alias("median_sale_price"),
            F.avg("price_per_sqft").cast("decimal(18,2)").alias("avg_price_per_sqft"),
            F.avg("days_to_close").cast("decimal(9,1)").alias("avg_days_to_close"),
        )
    )

    return {
        "dim_property": dim_property,
        "dim_agent": dim_agent,
        "dim_date": dim_date,
        "fact_sales": fact_sales,
        "fact_leases": fact_leases,
        "fact_listings": fact_listings,
        "agg_market_monthly": agg_market_monthly,
    }


def emit_freshness(silver: dict[str, DataFrame], metrics: Metrics) -> float:
    latest = None
    for df in silver.values():
        value = df.agg(F.max("_ingested_at")).first()[0]
        if value is not None and (latest is None or value > latest):
            latest = value
    if latest is None:
        return float("inf")
    if latest.tzinfo is None:
        latest = latest.replace(tzinfo=timezone.utc)
    minutes = (datetime.now(timezone.utc) - latest).total_seconds() / 60
    metrics.gauge("data.freshness_minutes", minutes)
    metrics.count("data.freshness.check")
    if minutes <= FRESHNESS_THRESHOLD_MINUTES:
        metrics.count("data.freshness.satisfied")
    return minutes


def run(spark: SparkSession, cfg: PlatformConfig, run_date: str, metrics: Metrics) -> dict[str, int]:
    silver = {name: spark.read.format("delta").load(cfg.table_path("silver", name)) for name in ENTITIES}
    counts = {}
    for name, df in build_tables(silver).items():
        df.write.format("delta").mode("overwrite").option("overwriteSchema", "true").save(cfg.table_path("gold", name))
        # Plain Parquet snapshot for Synapse dedicated SQL COPY INTO (synapse/dedicated).
        spark.read.format("delta").load(cfg.table_path("gold", name)).write.mode("overwrite").parquet(cfg.export_path(name, run_date))
        counts[name] = spark.read.format("delta").load(cfg.table_path("gold", name)).count()
        log.info("gold.%s: %d rows", name, counts[name])
    emit_freshness(silver, metrics)
    return counts
