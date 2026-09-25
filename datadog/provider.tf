terraform {
  required_version = ">= 1.6.0"
  required_providers {
    datadog = { source = "DataDog/datadog", version = "~> 3.70" }
  }

  # Same state account as the Azure platform, separate key:
  #   terraform init -backend-config=environments/dev/backend.hcl
  backend "azurerm" {}
}

# Credentials come from DD_API_KEY / DD_APP_KEY environment variables.
provider "datadog" { api_url = var.datadog_api_url }
