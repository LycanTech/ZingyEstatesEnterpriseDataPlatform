# Runbook: ADF pipeline failure

**Alert:** `ZingyEstates - ADF pipeline failure` · **Severity:** high in prod, medium in other environments

1. **Find the failed activity.** In ADF Studio, go to Monitor → Pipeline runs → `pl_master_daily`, and drill into the failed child pipeline. Or query Log Analytics:
   ```kusto
   ADFActivityRun | where Status == "Failed" and TimeGenerated > ago(6h)
   | project TimeGenerated, PipelineName, ActivityName, ErrorCode, ErrorMessage
   ```
2. **Match the error to a cause:**

   | Failing activity | Likely cause | Action |
   |---|---|---|
   | `Copy CRM table to landing` | CRM unreachable, credentials rotated, or table renamed | Check the `crm-sql-connection-string` secret. Test the linked service `ls_crm_sql`. |
   | `Copy listings API to landing` | API down, key expired, or response shape changed | Check the `listings-api-key` secret and the partner status page. Confirm `$.data` / `$.paging.next` still exist. |
   | Any copy activity, 403 on the lake | Managed private endpoint not approved, or a role assignment is missing | Check ADF → Manage → Managed private endpoints. Rerun the Terraform stage. |
   | `Run medallion job` | Databricks job failed | Go to [databricks-job-failure](databricks-job-failure.md). |
   | `Load warehouse` | Dedicated pool paused, or no exports for the date | Resume the pool. Check that `gold/_exports/<table>/run_date=<date>` exists. |

3. **Rerun** after the fix. Trigger `pl_master_daily` with the same `run_date`. It's idempotent.
4. If the source is still down after two hours, tell the report consumers that data is stale. Datadog's freshness SLO also tracks this.
