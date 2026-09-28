# Databricks and Spark (`DBX-*`)

Useful commands (CLI authenticated to the workspace; `DATABRICKS_HOST` is the Terraform output `databricks_workspace_url`):

```bash
databricks jobs list --name zingy-daily-medallion-<env>
databricks jobs list-runs --job-id <id> --limit 5
databricks jobs get-run-output <task-run-id>
databricks jobs run-now <id> --json '{"job_parameters": {"run_date": "YYYY-MM-DD"}}'
```

## DBX-01 `PERMISSION_DENIED` or 403 reading `abfss://` paths

**Symptom:** `PERMISSION_DENIED: User does not have READ FILES on External Location`, or `AbfsRestOperationException: Operation failed: "This request is not authorized", 403`.

**Cause:**
- The Unity Catalog external location or grant is missing for the job's run-as identity.
- The access connector lost **Storage Blob Data Contributor**.
- The lake firewall's trusted-instance rule for the access connector was removed.

**Fix now:**

```bash
bash scripts/setup-unity-catalog.sh <env> <storage-account> <access-connector-id>   # idempotent
databricks external-locations list
databricks grants get external_location zingy-<env>-silver
```

Rerun the Terraform stage to restore RBAC and firewall rules.

**Prevent:** CD runs `setup-unity-catalog.sh` on every deploy. If jobs run as a different principal, grant that principal too.

## DBX-02 `Metastore not assigned` or Unity Catalog not enabled

**Symptom:** `setup-unity-catalog.sh` fails with `METASTORE_DOES_NOT_EXIST`, or storage-credential commands fail.

**Cause:** The workspace has no Unity Catalog metastore. Older regions and accounts need one assigned manually.

**Fix now:** Databricks account console → Catalog → assign the regional metastore to `dbw-zingy-<env>`, or create one. Then rerun the Databricks job in CD.

**Prevent:** Add metastore assignment to environment onboarding.

## DBX-03 Cluster fails to start: `QuotaExceeded` / `CLOUD_PROVIDER_LAUNCH_FAILURE`

**Cause:** Not enough vCPU quota in the region for `node_type` × (`max_workers` + 1), or the VM SKU is unavailable.

**Fix now:** See [TF-07](04-terraform-and-azure.md#tf-07-regional-capacity-or-quota-errors-when-creating-resources). As a quick workaround, lower `max_workers` or change `node_type` for the target in `databricks/databricks.yml` and redeploy.

**Prevent:** Check quota before raising `max_workers`.

## DBX-04 Cluster fails: `SUBNET_EXHAUSTED` / not enough IP addresses

**Cause:** Each node uses one IP in both the host and container subnets (each /24, about 250 usable). Parallel jobs and interactive clusters add up.

**Fix now:** Terminate idle interactive clusters. Lower parallelism.

**Prevent:** Plan subnet size for peak node count. Resizing subnets requires recreating the workspace.

## DBX-05 `bundle deploy` fails

**Symptom:** Examples: `cannot resolve variable storage_account`, `no files match pattern: ../dist/*.whl`, `Error: failed to build artifact`, or a production-mode warning about `run_as`.

**Cause:** The `--var storage_account=...` argument is missing, the wheel build failed (the `build` package isn't installed, or `databricks/pyproject.toml` has errors), or you're running as a user in production mode.

**Fix now:**

```bash
cd databricks
python -m build --wheel          # does the wheel build?
databricks bundle validate -t <env> --var storage_account=<acct>
```

**Prevent:** Deploy qa, uat and prod only from CI (as the service principal). Use `-t dev` for personal testing.

## DBX-06 Job fails with `ModuleNotFoundError` or wrong code version on the cluster

**Cause:** A stale wheel from a previous deploy, or `libraries` pointing to the wrong path.

**Fix now:** `rm -rf databricks/dist && databricks bundle deploy -t <env> --var storage_account=<acct>`. Check the run's libraries tab for the wheel version.

**Prevent:** Bump `version` in `databricks/pyproject.toml` for releases so wheels are traceable.

## DBX-07 `DATA_SOURCE_NOT_FOUND` / `PATH_NOT_FOUND` warnings, and bronze has 0 rows for an entity

**Cause:** ADF didn't land files for that entity and date, and bronze skips it by design, with a warning.

**Fix now:** Check `landing/<source>/<entity>/ingest_date=<date>/`. Rerun the ADF ingestion, then rerun the job for that date.

**Prevent:** The freshness monitor catches this. Consider failing bronze when a **required** entity is missing.

## DBX-08 Silver `MERGE` fails: `DELTA_MULTIPLE_SOURCE_ROW_MATCHING_TARGET_ROW_IN_MERGE`

**Cause:** The source for the merge has duplicate keys. This shouldn't happen, because `latest_per_key` deduplicates, unless the key or order columns changed, or the `updated_at` values are identical and `_ingested_at` ties.

**Fix now:** Find the duplicates:

```python
df.groupBy("<key>").count().where("count > 1").show()
```

Make sure the entity's `key` in `entities.py` is really unique. Add a deterministic tie-breaker (for example `_source_file`) to `latest_per_key`.

**Prevent:** Add a test with exact-duplicate rows.

## DBX-09 `ConcurrentAppendException` / `DELTA_CONCURRENT_*`

**Cause:** Two runs wrote the same table at once: a manual run during the scheduled run, or an ADF retry overlapping a still-running job.

**Fix now:** Wait for the other run to finish, then repair the failed run (Databricks UI → run → **Repair run**).

**Prevent:** The job has `max_concurrent_runs: 1`. Don't start ad-hoc runs from notebooks against production tables.

## DBX-10 Bad data written: restore a Delta table

**Symptom:** A buggy release corrupted silver or gold.

**Fix now:**

```sql
DESCRIBE HISTORY delta.`abfss://silver@<acct>.dfs.core.windows.net/sales_transactions`;
RESTORE TABLE delta.`abfss://silver@<acct>.dfs.core.windows.net/sales_transactions` TO VERSION AS OF <n>;
```

Then fix the code and rerun the affected dates. Gold is fully rebuilt on the next run.

**Prevent:** Don't run `VACUUM` with less than 7 days' retention, because that removes time-travel history.

## DBX-11 Job is getting slower every week

**Cause:** Small files accumulating in silver from daily MERGE writes, growing history, or data skew.

**Fix now:**

```sql
OPTIMIZE delta.`abfss://silver@<acct>.dfs.core.windows.net/sales_transactions` ZORDER BY (property_id);
VACUUM   delta.`abfss://silver@<acct>.dfs.core.windows.net/sales_transactions` RETAIN 168 HOURS;
```

Check the Spark UI for skewed tasks and spill. Raise `max_workers` for the target.

**Prevent:** Add a weekly maintenance task to the bundle, or enable `delta.autoOptimize.optimizeWrite` and predictive optimization for Unity Catalog tables.

## DBX-12 `OutOfMemoryError` / executor lost

**Cause:** A large shuffle (for example `percentile_approx` over huge groups), a skewed join, or collecting to the driver.

**Fix now:** Use a larger `node_type` or more workers. Set `spark.sql.adaptive.skewJoin.enabled=true` (it's on by default in DBR). Avoid `.collect()` in pipeline code.

**Prevent:** Load-test gold on production-sized data in uat.

## DBX-13 Metrics secret missing: `Secret does not exist with scope: zingy-platform and key: datadog-api-key`

**Cause:** The secret scope was never created (CD's Databricks step didn't run), or it was deleted.

**Fix now:**

```bash
databricks secrets create-scope zingy-platform
printf '%s' "$DD_API_KEY" | databricks secrets put-secret zingy-platform datadog-api-key
```

**Prevent:** CD recreates it on every deploy.

## DBX-14 Behaviour changes after a Databricks runtime upgrade

**Symptom:** Casts that used to give NULL now error (ANSI mode), timestamps are off, or deprecated APIs fail (`input_file_name` in shared access mode).

**Cause:** A different `spark_version` in `databricks/resources/*.yml`.

**Fix now:** Pin back to the previous `spark_version` and redeploy, then investigate. This code already uses `try_cast` and `_metadata.file_path` to be safe under ANSI and Unity Catalog.

**Prevent:** Follow [AGE-01](12-aging-and-maintenance.md#age-01-databricks-runtime-154-lts-reaches-end-of-support). Upgrade dev first, then compare row counts and DQ metrics for a week.

## DBX-15 Job emails fail or go to the wrong people

**Cause:** The `alert_email` bundle variable still has its default value (`data-engineering@zingyestates.example`).

**Fix now:** Deploy with `--var alert_email=<real-address>`, or set it per target in `databricks.yml`.

**Prevent:** Set real addresses per target during onboarding.

## DBX-16 Workspace token or CLI auth fails locally: `default auth: cannot configure default credentials`

**Fix now:** Run `az login`, then:

```bash
export DATABRICKS_HOST=https://adb-<id>.<n>.azuredatabricks.net
export DATABRICKS_AUTH_TYPE=azure-cli
databricks current-user me
```

**Prevent:** Use `azure-cli` auth. Avoid personal access tokens.
