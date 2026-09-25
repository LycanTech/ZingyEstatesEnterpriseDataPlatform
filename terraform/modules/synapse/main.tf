data "azurerm_client_config" "current" {}

resource "azurerm_synapse_workspace" "this" {
  name                                 = var.name
  resource_group_name                  = var.resource_group_name
  location                             = var.location
  storage_data_lake_gen2_filesystem_id = "https://${var.storage_account_name}.dfs.core.windows.net/${var.storage_filesystem_name}"
  managed_resource_group_name          = "rg-${var.name}-managed"
  managed_virtual_network_enabled      = true
  azuread_authentication_only          = true
  public_network_access_enabled        = true
  tags                                 = var.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_synapse_workspace_aad_admin" "this" {
  synapse_workspace_id = azurerm_synapse_workspace.this.id
  login                = var.admin_group_name
  object_id            = var.admin_group_object_id
  tenant_id            = data.azurerm_client_config.current.tenant_id
}

# Corporate ranges only. CI adds and removes a temporary rule for the build
# agent while deploying SQL (scripts/deploy-synapse.sh).
resource "azurerm_synapse_firewall_rule" "allowed" {
  for_each = { for i, cidr in var.allowed_ip_ranges : "allowed-${i}" => cidr }

  name                 = each.key
  synapse_workspace_id = azurerm_synapse_workspace.this.id
  start_ip_address     = cidrhost(each.value, 0)
  end_ip_address       = cidrhost(each.value, -1)
}

resource "azurerm_synapse_sql_pool" "dedicated" {
  count = var.enable_dedicated_pool ? 1 : 0

  name                      = "dw_zingy"
  synapse_workspace_id      = azurerm_synapse_workspace.this.id
  sku_name                  = var.dedicated_pool_sku
  create_mode               = "Default"
  storage_account_type      = strcontains(var.storage_replication_type, "GRS") ? "GRS" : "LRS"
  geo_backup_policy_enabled = strcontains(var.storage_replication_type, "GRS")
  tags                      = var.tags
}

# SQL auditing to Azure Monitor (the workspace diagnostic setting forwards
# SQLSecurityAuditEvents to Log Analytics).
resource "azurerm_synapse_workspace_extended_auditing_policy" "this" {
  synapse_workspace_id   = azurerm_synapse_workspace.this.id
  log_monitoring_enabled = true
}

resource "azurerm_synapse_sql_pool_extended_auditing_policy" "dedicated" {
  count = var.enable_dedicated_pool ? 1 : 0

  sql_pool_id            = azurerm_synapse_sql_pool.dedicated[0].id
  log_monitoring_enabled = true
}

resource "azurerm_synapse_sql_pool_security_alert_policy" "dedicated" {
  count = var.enable_dedicated_pool ? 1 : 0

  sql_pool_id                  = azurerm_synapse_sql_pool.dedicated[0].id
  policy_state                 = "Enabled"
  email_account_admins_enabled = true
}

module "private_endpoints" {
  source = "../private_endpoint"
  for_each = {
    sql           = { subresource = "Sql", zone = "synapse_sql" }
    sql-on-demand = { subresource = "SqlOnDemand", zone = "synapse_sql" }
    dev           = { subresource = "Dev", zone = "synapse_dev" }
  }

  name                = "${var.name}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  resource_id         = azurerm_synapse_workspace.this.id
  subresource_name    = each.value.subresource
  private_dns_zone_id = var.private_dns_zone_ids[each.value.zone]
  tags                = var.tags
}
