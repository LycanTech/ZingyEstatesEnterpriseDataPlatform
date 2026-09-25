output "workspace_id" {
  value = azurerm_synapse_workspace.this.id
}

output "workspace_name" {
  value = azurerm_synapse_workspace.this.name
}

output "principal_id" {
  value = azurerm_synapse_workspace.this.identity[0].principal_id
}

output "serverless_sql_endpoint" {
  value = azurerm_synapse_workspace.this.connectivity_endpoints["sqlOnDemand"]
}

output "dedicated_sql_endpoint" {
  value = azurerm_synapse_workspace.this.connectivity_endpoints["sql"]
}

output "dedicated_pool_name" {
  description = "Empty when the dedicated pool is disabled."
  value       = var.enable_dedicated_pool ? azurerm_synapse_sql_pool.dedicated[0].name : ""
}
