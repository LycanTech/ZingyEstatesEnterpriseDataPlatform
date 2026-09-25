terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.6"
    }
  }

  # Partial configuration. Supply environments/<env>/backend.hcl at init time:
  #   terraform init -backend-config=environments/dev/backend.hcl
  backend "azurerm" {}
}

provider "azurerm" {
  # subscription_id is read from ARM_SUBSCRIPTION_ID.
  storage_use_azuread = true

  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
