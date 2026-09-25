data "azurerm_client_config" "current" {}

locals {
  name   = "${var.short_name}-${var.environment}"
  unique = "${var.short_name}-${var.environment}-${var.name_suffix}"

  tags = merge({
    company     = var.company
    environment = var.environment
    managed-by  = "terraform"
    service     = "data-platform"
    team        = "data-engineering"
  }, var.tags)
}

resource "azurerm_resource_group" "platform" {
  name     = "rg-${var.company}-${var.environment}-data"
  location = var.location
  tags     = local.tags
}

module "monitoring" {
  source = "./modules/monitoring"

  name                  = local.name
  resource_group_name   = azurerm_resource_group.platform.name
  location              = var.location
  retention_days        = var.log_retention_days
  alert_email_addresses = var.alert_email_addresses
  tags                  = local.tags
}

module "networking" {
  source = "./modules/networking"

  name                = local.name
  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  address_space       = var.vnet_address_space
  tags                = local.tags
}

module "storage" {
  source = "./modules/storage"

  name                          = "st${var.short_name}${var.environment}${var.name_suffix}dl"
  resource_group_name           = azurerm_resource_group.platform.name
  location                      = var.location
  replication_type              = var.storage_replication_type
  public_network_access_enabled = var.public_network_access_enabled
  private_endpoint_subnet_id    = module.networking.private_endpoint_subnet_id
  private_dns_zone_ids          = module.networking.private_dns_zone_ids
  tags                          = local.tags
}

# Lake firewall: deny by default, allow approved CIDRs, and allow the Synapse
# workspace and Databricks access connector as trusted resource instances.
resource "azurerm_storage_account_network_rules" "lake" {
  storage_account_id = module.storage.id
  default_action     = "Deny"
  bypass             = ["AzureServices", "Logging", "Metrics"]
  ip_rules           = var.allowed_ip_ranges

  private_link_access {
    endpoint_resource_id = module.synapse.workspace_id
  }

  private_link_access {
    endpoint_resource_id = module.databricks.access_connector_id
  }
}

module "key_vault" {
  source = "./modules/key_vault"

  name                          = "kv-${local.unique}"
  resource_group_name           = azurerm_resource_group.platform.name
  location                      = var.location
  public_network_access_enabled = var.public_network_access_enabled
  allowed_ip_ranges             = var.allowed_ip_ranges
  private_endpoint_subnet_id    = module.networking.private_endpoint_subnet_id
  private_dns_zone_ids          = module.networking.private_dns_zone_ids
  tags                          = local.tags
}

module "databricks" {
  source = "./modules/databricks"

  name                                = "dbw-${local.name}"
  resource_group_name                 = azurerm_resource_group.platform.name
  location                            = var.location
  sku                                 = var.databricks_sku
  virtual_network_id                  = module.networking.vnet_id
  host_subnet_name                    = module.networking.databricks_host_subnet_name
  container_subnet_name               = module.networking.databricks_container_subnet_name
  host_subnet_nsg_association_id      = module.networking.databricks_host_nsg_association_id
  container_subnet_nsg_association_id = module.networking.databricks_container_nsg_association_id
  tags                                = local.tags
}

module "data_factory" {
  source = "./modules/data_factory"

  name                = "adf-${local.unique}"
  resource_group_name = azurerm_resource_group.platform.name
  location            = var.location
  storage_account_id  = module.storage.id
  key_vault_id        = module.key_vault.id
  git_configuration   = var.adf_git_configuration
  tags                = local.tags
}

module "synapse" {
  source = "./modules/synapse"

  name                       = "syn-${local.unique}"
  resource_group_name        = azurerm_resource_group.platform.name
  location                   = var.location
  storage_account_name       = module.storage.name
  storage_filesystem_name    = module.storage.synapse_filesystem_name
  admin_group_name           = var.synapse_admin_group_name
  admin_group_object_id      = var.synapse_admin_group_object_id
  enable_dedicated_pool      = var.enable_synapse_dedicated_pool
  dedicated_pool_sku         = var.synapse_dedicated_pool_sku
  storage_replication_type   = var.storage_replication_type
  private_endpoint_subnet_id = module.networking.private_endpoint_subnet_id
  private_dns_zone_ids       = module.networking.private_dns_zone_ids
  allowed_ip_ranges          = var.allowed_ip_ranges
  tags                       = local.tags
}

# ---------------------------------------------------------------------------
# Identity and access: managed identities only, no account keys or SAS tokens.
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "adf_lake" {
  scope                = module.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.data_factory.principal_id
}

resource "azurerm_role_assignment" "adf_key_vault" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.data_factory.principal_id
}

# Lets the ADF linked service authenticate to Databricks with its managed identity.
resource "azurerm_role_assignment" "adf_databricks" {
  scope                = module.databricks.workspace_id
  role_definition_name = "Contributor"
  principal_id         = module.data_factory.principal_id
}

resource "azurerm_role_assignment" "databricks_lake" {
  scope                = module.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.databricks.access_connector_principal_id
}

resource "azurerm_role_assignment" "synapse_lake" {
  scope                = module.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.synapse.principal_id
}

resource "azurerm_role_assignment" "engineers_lake_read" {
  count = var.data_engineer_group_object_id == null ? 0 : 1

  scope                = module.storage.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.data_engineer_group_object_id
}

# ---------------------------------------------------------------------------
# Diagnostics: every platform resource ships logs and metrics to Log Analytics.
# Datadog collects Azure metrics separately through its integration (datadog/).
# ---------------------------------------------------------------------------

module "diagnostics" {
  source = "./modules/diagnostics"

  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  target_resource_ids = {
    storage-blob = "${module.storage.id}/blobServices/default"
    key-vault    = module.key_vault.id
    data-factory = module.data_factory.id
    databricks   = module.databricks.workspace_id
    synapse      = module.synapse.workspace_id
  }
}
