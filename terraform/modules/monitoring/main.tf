resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_days
  tags                = var.tags
}

# Azure-native alert fan-out. Primary data-platform alerting lives in Datadog
# (datadog/monitors.tf); this group covers platform-level Azure alerts.
resource "azurerm_monitor_action_group" "platform" {
  name                = "ag-${var.name}-platform"
  resource_group_name = var.resource_group_name
  short_name          = "zingydata"
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name                    = "email-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}
