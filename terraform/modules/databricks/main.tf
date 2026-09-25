resource "azurerm_databricks_workspace" "this" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.sku
  managed_resource_group_name   = "rg-${var.name}-managed"
  public_network_access_enabled = true
  tags                          = var.tags

  # VNet injection with secure cluster connectivity (no public IPs on nodes).
  custom_parameters {
    no_public_ip                                         = true
    virtual_network_id                                   = var.virtual_network_id
    public_subnet_name                                   = var.host_subnet_name
    private_subnet_name                                  = var.container_subnet_name
    public_subnet_network_security_group_association_id  = var.host_subnet_nsg_association_id
    private_subnet_network_security_group_association_id = var.container_subnet_nsg_association_id
  }
}

# Managed identity Unity Catalog uses as its storage credential for the lake.
resource "azurerm_databricks_access_connector" "this" {
  name                = "dbac-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}
