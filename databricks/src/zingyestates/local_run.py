"""End-to-end local demo: generate source data, then run bronze -> silver -> gold.

python -m zingyestates.local_run --base-dir .local-lake
"""

from __future__ import annotations

import argparse
import logging
from datetime import datetime, timezone

from delta.tables import DeltaTable
from pyspark.sql import functions as F

from zingyestates import bronze, gold, silver
from zingyestates.config import PlatformConfig
from zingyestates.metrics import Metrics
from zingyestates.sample_data import generate, write_landing
from zingyestates.spark import get_spark


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-dir", default=".local-lake")
    parser.add_argument("--run-date", default=datetime.now(timezone.utc).strftime("%Y-%m-%d"))
    parser.add_argument("--skip-generate", action="store_true", help="reuse files already in landing/")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    logging.getLogger("py4j").setLevel(logging.WARNING)

    cfg = PlatformConfig.for_local(args.base_dir)
    spark = get_spark("zingyestates-local")
    spark.sparkContext.setLogLevel("WARN")

    if not args.skip_generate:
        write_landing(spark, cfg, args.run_date, generate(args.run_date))

    results = {}
    for step, fn in (("bronze-ingestion", bronze.run), ("silver-transformation", silver.run), ("gold-modeling", gold.run)):
        metrics = Metrics.from_env("local", step)
        with metrics.pipeline_run():
            results[step] = fn(spark, cfg, args.run_date, metrics)

    print("\n=== Bronze rows ===")
    for name, n in results["bronze-ingestion"].items():
        print(f"  {name:<20} {n:>6}")
    print("\n=== Silver data quality ===")
    for name, r in results["silver-transformation"].items():
        print(f"  {name:<20} processed={r['processed']:<5} rejected={r['rejected']:<3} duplicates={r['duplicates']}")
    print("\n=== Gold tables ===")
    for name, n in results["gold-modeling"].items():
        print(f"  {name:<20} {n:>6}")

    print("\n=== Quarantined records (why) ===")
    for name in results["silver-transformation"]:
        path = cfg.table_path("quarantine", name)
        if not DeltaTable.isDeltaTable(spark, path):
            continue
        for row in spark.read.format("delta").load(path).select(F.explode("_dq_failures").alias("rule")).groupBy("rule").count().collect():
            print(f"  {name:<20} {row['rule']:<28} {row['count']}")

    print("\n=== Top markets by sales volume (gold.agg_market_monthly) ===")
    (
        spark.read.format("delta")
        .load(cfg.table_path("gold", "agg_market_monthly"))
        .groupBy("city", "state")
        .agg(F.sum("sales_count").alias("sales"), F.sum("total_volume").alias("volume"), F.avg("avg_price_per_sqft").alias("avg_ppsf"))
        .orderBy(F.desc("volume"))
        .show(10, truncate=False)
    )
    print(f"Lake written to {cfg.zone('landing').rsplit('/', 1)[0]}")


if __name__ == "__main__":
    main()
