"""Entry points for the Databricks wheel tasks (see databricks/resources/*.yml)."""

from __future__ import annotations

import argparse
import logging
import os
from collections.abc import Callable
from datetime import datetime, timezone

from zingyestates import bronze, gold, silver
from zingyestates.config import PlatformConfig
from zingyestates.metrics import Metrics
from zingyestates.spark import get_spark

log = logging.getLogger("zingyestates")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="ZingyEstates medallion step")
    parser.add_argument("--env", required=True, choices=["local", "dev", "qa", "uat", "prod"])
    parser.add_argument("--storage-account", default=os.getenv("ZINGY_STORAGE_ACCOUNT", ""))
    parser.add_argument("--local-base-dir", default=os.getenv("ZINGY_LOCAL_BASE_DIR", ".local-lake"))
    parser.add_argument("--run-date", default="", help="YYYY-MM-DD; defaults to today (UTC)")
    args = parser.parse_args(argv)
    args.run_date = args.run_date or datetime.now(timezone.utc).strftime("%Y-%m-%d")
    datetime.strptime(args.run_date, "%Y-%m-%d")  # validate
    return args


def config_from_args(args: argparse.Namespace) -> PlatformConfig:
    if args.env == "local":
        return PlatformConfig.for_local(args.local_base_dir)
    return PlatformConfig.for_azure(args.env, args.storage_account)


def _run_step(pipeline: str, step: Callable, argv: list[str] | None) -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    args = parse_args(argv)
    cfg = config_from_args(args)
    metrics = Metrics.from_env(args.env, pipeline)
    log.info("starting %s env=%s run_date=%s metrics=%s", pipeline, args.env, args.run_date, metrics.backend)
    with metrics.pipeline_run():
        result = step(get_spark(f"zingyestates-{pipeline}"), cfg, args.run_date, metrics)
    log.info("finished %s: %s", pipeline, result)


def bronze_main(argv: list[str] | None = None) -> None:
    _run_step("bronze-ingestion", bronze.run, argv)


def silver_main(argv: list[str] | None = None) -> None:
    _run_step("silver-transformation", silver.run, argv)


def gold_main(argv: list[str] | None = None) -> None:
    _run_step("gold-modeling", gold.run, argv)
