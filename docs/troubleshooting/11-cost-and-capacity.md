# Cost and capacity (`COST-*`)

Start with Cost Management → Cost analysis, grouped by **resource** and filtered to the tag `environment=<env>`.

```bash
az consumption usage list --start-date $(date -u -d '-7 days' +%F) --end-date $(date -u +%F) \
  --query "[].{resource:instanceName, cost:pretaxCost}" -o table | sort -k2 -n -r | head
```

## COST-01 Synapse dedicated pool left running

**Symptom:** A steady hourly charge on `dw_zingy`, even at night.

**Fix now:** `az synapse sql pool pause -g rg-zingyestates-<env>-data --workspace-name syn-zingy-<env>-<sfx> -n dw_zingy`

**Prevent:** Keep it disabled in dev and qa (`enable_synapse_dedicated_pool = false`). In uat, pause outside test windows with an Automation runbook or a scheduled workflow. Use serverless views wherever possible.

## COST-02 Databricks spend spike

**Cause:** A run that won't finish, a larger `max_workers`, interactive clusters left running, or retries.

**Fix now:**

```bash
databricks clusters list --output json | jq -r '.[] | select(.state=="RUNNING") | "\(.cluster_id) \(.cluster_name)"'
databricks clusters delete <cluster-id>       # terminates, doesn't delete config
databricks jobs list-runs --job-id <id> --active-only
databricks jobs cancel-run <run-id>
```

**Prevent:** Job clusters exist only for the run, and the job has `timeout_seconds: 7200`. Apply a cluster policy with auto-termination and max-worker caps for interactive clusters.

## COST-03 Log Analytics ingestion cost rising

**Cause:** `allLogs` diagnostics from noisy resources (storage read logs at high volume, Databricks verbose logs).

**Fix now:** Find the top tables:

```kusto
Usage | where TimeGenerated > ago(7d) | summarize GB = sum(Quantity) / 1000 by DataType | order by GB desc
```

Narrow `modules/diagnostics` to specific categories for the noisy resource, or use Basic logs tables.

**Prevent:** Set a daily cap in non-prod (`daily_quota_gb` on the workspace) and review monthly.

## COST-04 Storage growing faster than expected

**Cause:**
- Landing files are never cleaned beyond the lifecycle rule.
- Delta history is never vacuumed.
- `_exports` snapshots pile up (one per day, per table).
- Soft-deleted data counts towards storage.

**Fix now:**

```sql
VACUUM delta.`abfss://silver@<acct>.dfs.core.windows.net/sales_transactions` RETAIN 168 HOURS;
```

Delete old `_exports/<table>/run_date=*` folders older than a few days:

```bash
az storage fs directory delete -f gold -n "_exports/fact_sales/run_date=2026-08-01" --account-name <acct> --auth-mode login --yes
```

**Prevent:** Add a lifecycle rule for `gold/_exports/` (delete after 14 days) in `modules/storage`, and schedule weekly `VACUUM`.

## COST-05 ADF charges higher than expected

**Cause:** Managed-VNet IR time-to-live, frequent debug runs, or large copies with many DIUs.

**Fix now:** Check ADF → Monitor → billing per pipeline (`PipelineBillingEnabled` is on in the factory). Lower the IR `timeToLive` if runs are sparse.

**Prevent:** Debug in dev only. Use sensible DIUs on copy activities.

## COST-06 Budget alert needed or exceeded

**Fix now:** Create or adjust a budget per environment resource group:

```bash
az consumption budget create --budget-name zingy-<env> --amount 500 --time-grain Monthly \
  --start-date $(date -u +%Y-%m-01) --end-date 2027-12-31 --resource-group rg-zingyestates-<env>-data --category cost
```

**Prevent:** Add `azurerm_consumption_budget_resource_group` to Terraform with notifications to the action group.

## COST-07 Growth: jobs, tables and warehouse outgrow current sizing

**Symptom:** Runs creep past the SLA, and Synapse queries slow down month after month.

**Fix now:** Scale temporarily (`max_workers`, DWU). Run `OPTIMIZE` ([DBX-11](06-databricks-and-spark.md#dbx-11-job-is-getting-slower-every-week)).

**Prevent:** Review quarterly. Revisit the design choices that were simple at small scale:
- Full CRM extracts could become incremental (watermark on `updated_at`).
- Full gold rebuilds could become incremental MERGE for the facts.
- Consider partitioning large silver tables.
