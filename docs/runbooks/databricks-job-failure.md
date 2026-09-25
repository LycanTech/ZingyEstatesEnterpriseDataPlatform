# Runbook: Databricks transformation failure

**Alert:** `ZingyEstates - Databricks transformation failure`, plus the job's failure email

1. Open **Workflows → `zingy-daily-medallion-<env>`** and check which task failed (`bronze_ingestion`, `silver_transformation`, or `gold_modeling`). Read the driver log.
2. **Match the error to a cause:**

   | Error | Cause | Action |
   |---|---|---|
   | `PERMISSION_DENIED` / `403` on `abfss://` | Unity Catalog external location or grant missing | Rerun `scripts/setup-unity-catalog.sh <env> <account> <connector-id>`. |
   | `PATH_NOT_FOUND` for landing (warning only) | ADF didn't land that entity | Bronze skips the entity. Check the ADF copy for it. |
   | Schema mismatch in `MERGE` | Source added or renamed columns | Update `entities.py`. Bronze accepts new columns (`mergeSchema`), but silver projects only known columns. |
   | `DELTA_CONCURRENT_*` | Two runs overlapped | `max_concurrent_runs: 1` should prevent this. Check for a manual run. |
   | Cluster start failure | Quota or subnet IPs exhausted | Check the vCPU quota. The Databricks subnets are /24. |

3. Fix, deploy (a PR, or `make bundle-deploy ENV=dev` for dev), then **repair the run** from the failed task in the Databricks UI. You can also rerun `pl_transform_databricks` in ADF.

## Slow runs

Alert: `Data pipeline duration anomaly` (> 20 minutes).

- Check the Spark UI for skew and spill, and use `DESCRIBE HISTORY` to see file counts.
- Run `OPTIMIZE` / `VACUUM` on the large silver tables. Consider a scheduled maintenance task.
- Raise `max_workers` for the target in `databricks/databricks.yml`.
