"""Landing -> Bronze: land files as Delta with ingestion metadata, no business logic."""

from __future__ import annotations

import logging

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.utils import AnalysisException

from zingyestates.config import PlatformConfig
from zingyestates.entities import ENTITIES, Entity
from zingyestates.metrics import Metrics

log = logging.getLogger(__name__)


def ingest_entity(spark: SparkSession, cfg: PlatformConfig, entity: Entity, run_date: str) -> int:
    source = cfg.landing_path(entity.source, entity.name, run_date)
    try:
        raw = spark.read.format(entity.file_format).load(source)
    except AnalysisException as exc:
        if "PATH_NOT_FOUND" in str(exc) or "Path does not exist" in str(exc):
            log.warning("No landing data for %s on %s at %s", entity.name, run_date, source)
            return 0
        raise

    df = (
        raw.withColumn("_ingested_at", F.current_timestamp())
        .withColumn("_source_file", F.col("_metadata.file_path"))
        .withColumn("_run_date", F.lit(run_date).cast("date"))
    )

    # Idempotent per run date: a re-run replaces that day's partition only.
    (
        df.write.format("delta")
        .mode("overwrite")
        .option("replaceWhere", f"_run_date = '{run_date}'")
        .option("mergeSchema", "true")
        .partitionBy("_run_date")
        .save(cfg.table_path("bronze", entity.name))
    )
    count = df.count()
    log.info("bronze.%s: %d rows for %s", entity.name, count, run_date)
    return count


def run(spark: SparkSession, cfg: PlatformConfig, run_date: str, metrics: Metrics) -> dict[str, int]:
    counts = {}
    for entity in ENTITIES.values():
        counts[entity.name] = ingest_entity(spark, cfg, entity, run_date)
        metrics.gauge("databricks.records_processed", counts[entity.name], source=entity.source, entity=entity.name, zone="bronze")
    return counts
