"""Runs the whole medallion flow against a temporary local lake."""

import pytest

from zingyestates import bronze, gold, silver
from zingyestates.config import PlatformConfig
from zingyestates.metrics import Metrics
from zingyestates.sample_data import generate, write_landing

pytestmark = pytest.mark.spark

RUN_DATE = "2026-09-25"


@pytest.fixture(scope="module")
def lake(spark, tmp_path_factory):
    cfg = PlatformConfig.for_local(tmp_path_factory.mktemp("lake"))
    write_landing(spark, cfg, RUN_DATE, generate(RUN_DATE, n_properties=60, n_agents=8))
    return cfg


def _run_all(spark, cfg):
    metrics = Metrics("local", "test")
    return (
        bronze.run(spark, cfg, RUN_DATE, metrics),
        silver.run(spark, cfg, RUN_DATE, metrics),
        gold.run(spark, cfg, RUN_DATE, metrics),
        metrics,
    )


def test_end_to_end(spark, lake):
    bronze_counts, silver_results, gold_counts, metrics = _run_all(spark, lake)

    assert all(n > 0 for n in bronze_counts.values())
    # Deliberate defects in sample_data.generate
    assert silver_results["properties"]["rejected"] == 2
    assert silver_results["agents"]["rejected"] == 1
    assert silver_results["sales_transactions"]["rejected"] == 2
    assert silver_results["sales_transactions"]["duplicates"] == 1
    assert silver_results["leases"]["rejected"] == 1
    assert silver_results["listings"]["rejected"] == 1

    assert set(gold_counts) == {"dim_property", "dim_agent", "dim_date", "fact_sales", "fact_leases", "fact_listings", "agg_market_monthly"}
    assert gold_counts["dim_property"] == bronze_counts["properties"] - 2
    assert gold_counts["dim_date"] >= 365

    names = {m[0] for m in metrics.emitted}
    assert "zingyestates.data.quality.rejection_rate" in names
    assert "zingyestates.data.freshness_minutes" in names

    export = spark.read.parquet(lake.export_path("fact_sales", RUN_DATE))
    assert export.count() == gold_counts["fact_sales"]


def test_rerun_is_idempotent(spark, lake):
    first = _run_all(spark, lake)
    second = _run_all(spark, lake)
    assert first[0] == second[0]
    assert first[2] == second[2]
    silver_sales = spark.read.format("delta").load(lake.table_path("silver", "sales_transactions"))
    assert silver_sales.count() == silver_sales.select("transaction_id").distinct().count()
