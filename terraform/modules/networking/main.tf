locals {
  private_dns_zones = {
    blob        = "privatelink.blob.core.windows.net"
    dfs         = "privatelink.dfs.core.windows.net"
    vault       = "privatelink.vaultcore.azure.net"
    synapse_sql = "privatelink.sql.azuresynapse.net"
    synapse_dev = "privatelink.dev.azuresynapse.net"
  }
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = "snet-private-endpoints"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [cidrsubnet(var.address_space, 4, 0)]
  private_endpoint_network_policies = "Enabled"
}

# Databricks VNet injection needs two delegated subnets ("host"/public and "container"/private).
resource "azurerm_subnet" "databricks" {
  for_each = {
    host      = cidrsubnet(var.address_space, 2, 1)
    container = cidrsubnet(var.address_space, 2, 2)
  }

  name                 = "snet-databricks-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value]

  delegation {
    name = "databricks"
    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
        "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action",
      ]
    }
  }
}

# Databricks manages the rules on these NSGs itself.
resource "azurerm_network_security_group" "databricks" {
  name                = "nsg-${var.name}-databricks"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "databricks" {
  for_each = azurerm_subnet.databricks

  subnet_id                 = each.value.id
  network_security_group_id = azurerm_network_security_group.databricks.id
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-${var.name}-private-endpoints"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  security_rule {
    name                       = "allow-vnet-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "1433"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

resource "azurerm_private_dns_zone" "this" {
  for_each = local.private_dns_zones

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = azurerm_private_dns_zone.this

  name                  = "link-${var.name}-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.this.id
  tags                  = var.tags
}
