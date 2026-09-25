output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "private_endpoint_subnet_id" {
  value = azurerm_subnet.private_endpoints.id
}

output "databricks_host_subnet_name" {
  value = azurerm_subnet.databricks["host"].name
}

output "databricks_container_subnet_name" {
  value = azurerm_subnet.databricks["container"].name
}

output "databricks_host_nsg_association_id" {
  value = azurerm_subnet_network_security_group_association.databricks["host"].id
}

output "databricks_container_nsg_association_id" {
  value = azurerm_subnet_network_security_group_association.databricks["container"].id
}

output "private_dns_zone_ids" {
  description = "Map of zone key (blob, dfs, vault, synapse_sql, synapse_dev) to private DNS zone ID."
  value       = { for k, z in azurerm_private_dns_zone.this : k => z.id }
}
