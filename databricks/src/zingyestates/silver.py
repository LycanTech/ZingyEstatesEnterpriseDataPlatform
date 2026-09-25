"""Bronze -> Silver: type, standardise, validate, de-duplicate and upsert."""

from __future__ import annotations

import logging

from delta.tables import DeltaTable
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F

from zingyestates.config import PlatformConfig
from zingyestates.entities import ENTITIES, LOWERCASE_COLUMNS, UPPERCASE_COLUMNS, Entity
from zingyestates.metrics import Metrics
from zingyestates.quality import RULES, apply_rules, latest_per_key

log = logging.getLogger(__name__)

METADATA_COLUMNS = ["_ingested_at", "_source_file", "_run_date"]


def conform(df: DataFrame, entity: Entity) -> DataFrame:
    """Project onto the silver schema. Unparseable values become NULL (and then fail DQ)."""
    cols = []
    for name, dtype in entity.columns:
        if name not in df.columns:
            cols.append(F.lit(None).cast(dtype).alias(name))
            continue
        col = F.expr(f"try_cast(`{name}` AS {dtype})")
        if dtype == "string":
            col = F.trim(col)
            if name in UPPERCASE_COLUMNS:
                col = F.upper(col)
            elif name in LOWERCASE_COLUMNS:
                col = F.lower(col)
            col = F.when(col == "", None).otherwise(col)
        cols.append(col.alias(name))
    return df.select(*cols, *[c for c in METADATA_COLUMNS if c in df.columns])


def upsert(spark: SparkSession, df: DataFrame, path: str, key: str) -> None:
    if DeltaTable.isDeltaTable(spark, path):
        (
            DeltaTable.forPath(spark, path)
            .alias("t")
            .merge(df.alias("s"), f"t.{key} = s.{key}")
            .whenMatchedUpdateAll(condition="s.updated_at >= t.updated_at OR t.updated_at IS NULL")
            .whenNotMatchedInsertAll()
            .execute()
        )
    else:
        df.write.format("delta").save(path)


def transform_entity(spark: SparkSession, cfg: PlatformConfig, entity: Entity, run_date: str, metrics: Metrics) -> dict[str, int]:
    bronze_path = cfg.table_path("bronze", entity.name)
    if not DeltaTable.isDeltaTable(spark, bronze_path):
        log.warning("bronze.%s does not exist yet; skipping", entity.name)
        return {"processed": 0, "rejected": 0, "duplicates": 0}

    bronze = spark.read.format("delta").load(bronze_path).where(F.col("_run_date") == F.lit(run_date).cast("date"))
    typed = conform(bronze, entity).cache()
    valid, rejected = apply_rules(typed, RULES[entity.name])
    deduped = latest_per_key(valid, entity.key).withColumn("_silver_updated_at", F.current_timestamp())

    processed = typed.count()
    rejected_count = rejected.count()
    valid_count = processed - rejected_count
    duplicates = valid_count - deduped.count()

    upsert(spark, deduped, cfg.table_path("silver", entity.name), entity.key)
    (
        rejected.write.format("delta")
        .mode("overwrite")
        .option("replaceWhere", f"_run_date = '{run_date}'")
        .partitionBy("_run_date")
        .save(cfg.table_path("quarantine", entity.name))
    )
    typed.unpersist()

    tags = {"source": entity.source, "entity": entity.name}
    metrics.gauge("data.quality.records_processed", processed, **tags)
    metrics.gauge("data.quality.records_rejected", rejected_count, **tags)
    metrics.gauge("data.quality.rejection_rate", rejected_count / processed if processed else 0.0, **tags)
    metrics.gauge("data.quality.duplicates", duplicates, **tags)
    log.info("silver.%s: processed=%d rejected=%d duplicates=%d", entity.name, processed, rejected_count, duplicates)
    return {"processed": processed, "rejected": rejected_count, "duplicates": duplicates}


def run(spark: SparkSession, cfg: PlatformConfig, run_date: str, metrics: Metrics) -> dict[str, dict[str, int]]:
    return {name: transform_entity(spark, cfg, entity, run_date, metrics) for name, entity in ENTITIES.items()}
