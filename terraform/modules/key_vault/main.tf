data "azurerm_client_config" "current" {}

# Holds source-system credentials (CRM SQL connection string, listings API key).
# Secrets are set out-of-band by an operator; Terraform manages only the vault.
resource "azurerm_key_vault" "this" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = var.public_network_access_enabled
  tags                          = var.tags

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.allowed_ip_ranges
  }
}

module "private_endpoint" {
  source = "../private_endpoint"

  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  resource_id         = azurerm_key_vault.this.id
  subresource_name    = "vault"
  private_dns_zone_id = var.private_dns_zone_ids["vault"]
  tags                = var.tags
}
