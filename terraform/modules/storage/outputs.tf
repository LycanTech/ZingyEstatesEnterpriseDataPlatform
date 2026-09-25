output "id" {
  value = azurerm_storage_account.this.id
}

output "name" {
  value = azurerm_storage_account.this.name
}

output "dfs_endpoint" {
  value = azurerm_storage_account.this.primary_dfs_endpoint
}

output "synapse_filesystem_name" {
  value = azurerm_storage_container.filesystems["synapse"].name
}
