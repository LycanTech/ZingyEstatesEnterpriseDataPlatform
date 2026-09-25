# Operations

## Daily schedule

| Time (UTC) | What | Owner |
|---|---|---|
| 02:00 | `tr_daily_0200_utc` starts `pl_master_daily` | ADF |
| ~02:00–02:20 | CRM and listings ingestion to `landing/` | ADF |
| ~02:20–03:00 | `zingy-daily-medallion-<env>` job: bronze, silver, gold | Databricks |
| ~03:00–03:15 | `dw.usp_load_all` (uat/prod) | Synapse |
| 03:30 | Power BI dataset refresh | Power BI |

## First deployment

After the first successful pipeline run in an environment:

1. **Approve the ADF managed private endpoints** (`mpe-lake-dfs`, `mpe-key-vault`):
   ```bash
   for id in $(az network private-endpoint-connection list --id <storage-or-kv-id> --query "[?properties.privateLinkServiceConnectionState.status=='Pending'].id" -o tsv); do
     az network private-endpoint-connection approve --id "$id" --description "ADF managed VNet"
   done
   ```
2. **Load source secrets** into Key Vault:
   ```bash
   az keyvault secret set --vault-name kv-zingy-<env>-<suffix> --name crm-sql-connection-string --value '<connection string>'
   az keyvault secret set --vault-name kv-zingy-<env>-<suffix> --name listings-api-key --value '<key>'
   ```
3. **Enable the Datadog Azure integration** app registration with Monitoring Reader on the subscription (see `datadog/README.md`).
4. Run `scripts/smoke-test-adf.sh` or trigger `pl_master_daily` from ADF Studio.

## Rerunning a day

Every step is idempotent by run date.

- **Whole day:** in ADF Studio, trigger `pl_master_daily` with `run_date = YYYY-MM-DD`.
- **Transform only:** in Databricks, run `zingy-daily-medallion-<env>` with the job parameter `run_date`.
- **Warehouse only:** `EXEC dw.usp_load_all @run_date = 'YYYY-MM-DD', @storage_account = '<account>';`

## Monitoring

| Signal | Tool | Runbook |
|---|---|---|
| ADF pipeline failure | Datadog `ZingyEstates - ADF pipeline failure` | [adf-pipeline-failure](runbooks/adf-pipeline-failure.md) |
| Databricks job failure | Datadog `ZingyEstates - Databricks transformation failure`, plus job email | [databricks-job-failure](runbooks/databricks-job-failure.md) |
| DQ rejection rate > 1% | Datadog `ZingyEstates - Data quality rejection rate` | [data-quality-breach](runbooks/data-quality-breach.md) |
| Freshness > 30 min after run | Datadog `ZingyEstates - Data freshness breach` | [freshness-breach](runbooks/freshness-breach.md) |
| Pipeline duration > 20 min | Datadog `ZingyEstates - Data pipeline duration anomaly` | [databricks-job-failure](runbooks/databricks-job-failure.md#slow-runs) |
| SLOs | Datadog: pipeline success 99.5%, freshness 99.0% (30 days) | — |
| Resource logs | Log Analytics `log-zingy-<env>` | — |

## Useful queries

```sql
-- Synapse dedicated: last loads
SELECT TOP 20 * FROM dw.load_audit ORDER BY finished_at DESC;
```

```python
# Databricks: why were rows quarantined today?
spark.read.format("delta").load("abfss://quarantine@<account>.dfs.core.windows.net/sales_transactions") \
  .where("_run_date = current_date()").selectExpr("explode(_dq_failures) rule").groupBy("rule").count().show()
```

```kusto
// Log Analytics: failed ADF activity runs
ADFActivityRun | where Status == "Failed" | project TimeGenerated, PipelineName, ActivityName, ErrorMessage | order by TimeGenerated desc
```

## Cost controls

- Databricks job clusters exist only for the run, with capped autoscaling per target (`databricks/databricks.yml`).
- The Synapse dedicated pool is off in dev and qa. Pause it in uat outside test windows: `az synapse sql pool pause`.
- ADF integration runtime TTL is 10 minutes.
- Lake lifecycle tiering moves landing data to cool storage after 30 days.
