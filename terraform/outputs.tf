# Consumed by the deployment pipeline (pipelines/templates/terraform-outputs.yml)
# to configure the Databricks, Data Factory and Synapse deployments.

output "resource_group_name" {
  value = azurerm_resource_group.platform.name
}

output "storage_account_name" {
  value = module.storage.name
}

output "key_vault_name" {
  value = module.key_vault.name
}

output "key_vault_uri" {
  value = module.key_vault.uri
}

output "data_factory_name" {
  value = module.data_factory.name
}

output "data_factory_id" {
  value = module.data_factory.id
}

output "databricks_workspace_id" {
  value = module.databricks.workspace_id
}

output "databricks_workspace_url" {
  value = module.databricks.workspace_url
}

output "databricks_access_connector_id" {
  value = module.databricks.access_connector_id
}

output "synapse_workspace_name" {
  value = module.synapse.workspace_name
}

output "synapse_serverless_endpoint" {
  value = module.synapse.serverless_sql_endpoint
}

output "synapse_dedicated_endpoint" {
  value = module.synapse.dedicated_sql_endpoint
}

output "synapse_dedicated_pool_name" {
  value = module.synapse.dedicated_pool_name
}

output "log_analytics_workspace_id" {
  value = module.monitoring.log_analytics_workspace_id
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "location" {
  value = azurerm_resource_group.platform.location
}

output "synapse_dedicated_enabled" {
  value = var.enable_synapse_dedicated_pool
}
