# Runbook: data freshness breach

**Alert:** `ZingyEstates - Data freshness breach` (`zingyestates.data.freshness_minutes` > 30)

Freshness is measured at the end of the gold step as the minutes since the newest silver `_ingested_at`. A breach means gold was rebuilt from old data, or that the gold step itself didn't run.

1. **Did today's run happen?** Check ADF Monitor for `pl_master_daily`. If there's no run, check that `tr_daily_0200_utc` is **Started**. The ADF deployment stops triggers and restarts them. If a deployment failed partway through, the triggers can be left stopped.
2. **Did ingestion land data?** Check `landing/<source>/<entity>/ingest_date=<today>/` for each entity. If a folder is missing, bronze skipped that entity. Go to [adf-pipeline-failure](adf-pipeline-failure.md).
3. **Did the job run late?** A long bronze or silver step delays gold. Go to [databricks-job-failure](databricks-job-failure.md#slow-runs).
4. Once the data is current, rerun the day and confirm the SLO widget recovers.
