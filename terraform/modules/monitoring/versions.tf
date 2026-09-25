terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.14" # upper bound is set by the root module (terraform/versions.tf)
    }
  }
}
