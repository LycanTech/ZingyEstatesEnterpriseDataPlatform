"""SparkSession factory that works on Databricks and locally."""

from __future__ import annotations

import os

from pyspark.sql import SparkSession


def get_spark(app_name: str = "zingyestates") -> SparkSession:
    # On Databricks the session already exists and Delta is built in.
    if "DATABRICKS_RUNTIME_VERSION" in os.environ:
        return SparkSession.builder.getOrCreate()

    from delta import configure_spark_with_delta_pip

    builder = (
        SparkSession.builder.appName(app_name)
        .master(os.getenv("SPARK_MASTER", "local[*]"))
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog")
        .config("spark.sql.shuffle.partitions", "4")
        .config("spark.sql.session.timeZone", "UTC")
        .config("spark.ui.enabled", "false")
    )
    return configure_spark_with_delta_pip(builder).getOrCreate()
