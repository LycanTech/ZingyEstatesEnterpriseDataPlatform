resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = var.target_resource_ids

  name                       = "diag-to-log-analytics"
  target_resource_id         = each.value
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
