resource "datadog_integration_azure" "zingyestates" {
  tenant_name                 = var.azure_tenant_id
  client_id                   = var.azure_client_id
  client_secret               = var.azure_client_secret
  metrics_enabled             = true
  resource_collection_enabled = true
  usage_metrics_enabled       = true
  automute                    = true
  host_filters                = "company:zingyestates,env:${var.environment}"
}
