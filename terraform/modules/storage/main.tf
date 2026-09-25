locals {
  # Medallion zones plus supporting file systems.
  #   landing    - raw files exactly as ADF copied them
  #   bronze     - append-only Delta, schema-on-read + ingestion metadata
  #   silver     - cleansed, conformed, de-duplicated Delta
  #   gold       - business models (dimensions/facts) and Synapse export snapshots
  #   quarantine - records rejected by data-quality rules
  #   catalog    - Unity Catalog managed storage
  #   synapse    - Synapse workspace primary file system
  filesystems = ["landing", "bronze", "silver", "gold", "quarantine", "catalog", "synapse"]
}

resource "azurerm_storage_account" "this" {
  name                              = var.name
  resource_group_name               = var.resource_group_name
  location                          = var.location
  account_kind                      = "StorageV2"
  account_tier                      = "Standard"
  account_replication_type          = var.replication_type
  is_hns_enabled                    = true
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false
  local_user_enabled                = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true
  public_network_access_enabled     = var.public_network_access_enabled
  tags                              = var.tags

  # Firewall rules live in the root module (azurerm_storage_account_network_rules)
  # because they reference the Synapse and Databricks identities that depend on
  # this account.

  blob_properties {
    delete_retention_policy {
      days = 14
    }
    container_delete_retention_policy {
      days = 14
    }
  }
}

# Created through the ARM control plane (storage_account_id), so this works even
# when the data-plane firewall blocks the build agent.
resource "azurerm_storage_container" "filesystems" {
  for_each = toset(local.filesystems)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "this" {
  storage_account_id = azurerm_storage_account.this.id

  rule {
    name    = "landing-tiering"
    enabled = true
    filters {
      prefix_match = ["landing/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 30
        delete_after_days_since_modification_greater_than       = 400
      }
    }
  }

  rule {
    name    = "quarantine-expiry"
    enabled = true
    filters {
      prefix_match = ["quarantine/"]
      blob_types   = ["blockBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 180
      }
    }
  }
}

module "private_endpoints" {
  source   = "../private_endpoint"
  for_each = toset(["blob", "dfs"])

  name                = "${var.name}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  resource_id         = azurerm_storage_account.this.id
  subresource_name    = each.key
  private_dns_zone_id = var.private_dns_zone_ids[each.key]
  tags                = var.tags
}
