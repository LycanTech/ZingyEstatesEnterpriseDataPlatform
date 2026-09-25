locals { tags = ["company:${var.company}", "env:${var.environment}", "managed-by:terraform", "team:data-engineering"] }
resource "datadog_monitor" "adf_failures" {
  name    = "ZingyEstates - ADF pipeline failure"
  type    = "query alert"
  query   = "sum(last_15m):azure.datafactory.pipeline_failed{company:${var.company},env:${var.environment}} > 0"
  message = "🚨 ZingyEstates ADF pipeline failure. Investigate ADF, Databricks, data quality, and downstream loads. Runbook: docs/runbooks/adf-pipeline-failure.md ${var.notification_handle}"
  monitor_thresholds { critical = 0 }
  evaluation_delay    = 300
  notify_no_data      = false
  include_tags        = true
  require_full_window = false
  tags                = local.tags
}
resource "datadog_monitor" "data_quality" {
  name    = "ZingyEstates - Data quality rejection rate"
  type    = "query alert"
  query   = "avg(last_15m):zingyestates.data.quality.rejection_rate{env:${var.environment}} > 0.01"
  message = "⚠️ Data-quality rejection rate is above 1%. Check quarantine records and source schema changes. Runbook: docs/runbooks/data-quality-breach.md ${var.notification_handle}"
  monitor_thresholds { critical = 0.01 }
  notify_no_data      = false
  include_tags        = true
  require_full_window = false
  tags                = local.tags
}
resource "datadog_monitor" "freshness" {
  name    = "ZingyEstates - Data freshness breach"
  type    = "query alert"
  query   = "max(last_15m):zingyestates.data.freshness_minutes{env:${var.environment}} > 30"
  message = "🚨 ZingyEstates data freshness exceeded 30 minutes. Runbook: docs/runbooks/freshness-breach.md ${var.notification_handle}"
  monitor_thresholds { critical = 30 }
  notify_no_data      = false
  include_tags        = true
  require_full_window = false
  tags                = local.tags
}
resource "datadog_monitor" "databricks_failure" {
  name    = "ZingyEstates - Databricks transformation failure"
  type    = "query alert"
  query   = "sum(last_15m):zingyestates.databricks.job.failed{env:${var.environment}} > 0"
  message = "🚨 ZingyEstates Databricks transformation failed. Review the job, Spark error, source data, and recent deployment. Runbook: docs/runbooks/databricks-job-failure.md ${var.notification_handle}"
  monitor_thresholds { critical = 0 }
  notify_no_data      = false
  include_tags        = true
  require_full_window = false
  tags                = local.tags
}
resource "datadog_monitor" "pipeline_duration" {
  name    = "ZingyEstates - Data pipeline duration anomaly"
  type    = "query alert"
  query   = "avg(last_30m):zingyestates.data.pipeline.duration_seconds{env:${var.environment}} > 1200"
  message = "⚠️ Pipeline duration exceeded 20 minutes. Runbook: docs/runbooks/databricks-job-failure.md ${var.notification_handle}"
  monitor_thresholds { critical = 1200 }
  notify_no_data      = false
  include_tags        = true
  require_full_window = false
  tags                = local.tags
}
