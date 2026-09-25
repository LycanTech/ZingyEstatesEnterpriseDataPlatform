resource "azurerm_data_factory" "this" {
  name                            = var.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  managed_virtual_network_enabled = true
  public_network_enabled          = true
  tags                            = var.tags

  identity {
    type = "SystemAssigned"
  }

  # Only the dev factory is Git-connected; higher environments receive the
  # ARM template exported by CI (see adf/ and pipelines/templates/adf-*.yml).
  dynamic "vsts_configuration" {
    for_each = var.git_configuration == null ? [] : [var.git_configuration]
    content {
      account_name    = vsts_configuration.value.account_name
      project_name    = vsts_configuration.value.project_name
      repository_name = vsts_configuration.value.repository_name
      branch_name     = vsts_configuration.value.branch_name
      root_folder     = vsts_configuration.value.root_folder
      tenant_id       = vsts_configuration.value.tenant_id
    }
  }
}

# The managed-VNet integration runtime (ir-managed-vnet) is defined in
# adf/integrationRuntime so ADF Studio and the CI export can validate against it.

# Managed private endpoints from the ADF managed VNet. Each creates a pending
# private-endpoint connection on the target that must be approved once
# (docs/operations.md, "First deployment").
resource "azurerm_data_factory_managed_private_endpoint" "lake_dfs" {
  name               = "mpe-lake-dfs"
  data_factory_id    = azurerm_data_factory.this.id
  target_resource_id = var.storage_account_id
  subresource_name   = "dfs"
}

resource "azurerm_data_factory_managed_private_endpoint" "key_vault" {
  name               = "mpe-key-vault"
  data_factory_id    = azurerm_data_factory.this.id
  target_resource_id = var.key_vault_id
  subresource_name   = "vault"
}
