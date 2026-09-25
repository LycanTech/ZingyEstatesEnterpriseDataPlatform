variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "uat", "prod"], var.environment)
    error_message = "environment must be one of dev, qa, uat, prod."
  }
}

variable "location" {
  description = "Primary Azure region."
  type        = string
  default     = "eastus2"
}

variable "company" {
  description = "Company tag value."
  type        = string
  default     = "zingyestates"
}

variable "short_name" {
  description = "Short prefix used in resource names with tight length limits."
  type        = string
  default     = "zingy"
}

variable "name_suffix" {
  description = "Short organisation-unique suffix that keeps globally-unique names (storage, key vault, ADF, Synapse) available."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,4}$", var.name_suffix))
    error_message = "name_suffix must be 2-4 lowercase alphanumeric characters."
  }
}

variable "vnet_address_space" {
  description = "Address space for the platform virtual network (a /22 or larger)."
  type        = string
}

variable "allowed_ip_ranges" {
  description = "Public CIDRs allowed through storage/key vault/Synapse firewalls (for example the corporate egress range). Keep empty in prod."
  type        = list(string)
  default     = []
}

variable "public_network_access_enabled" {
  description = "Allow firewalled public-network access to data-plane endpoints. Disable once self-hosted/private build agents exist."
  type        = bool
  default     = true
}

variable "storage_replication_type" {
  description = "ADLS Gen2 replication (LRS, ZRS, GRS, RAGZRS)."
  type        = string
  default     = "ZRS"
}

variable "databricks_sku" {
  description = "Databricks workspace SKU. Premium is required for Unity Catalog and access control."
  type        = string
  default     = "premium"
}

variable "synapse_admin_group_name" {
  description = "Display name of the Entra ID group that administers Synapse."
  type        = string
}

variable "synapse_admin_group_object_id" {
  description = "Object ID of the Entra ID group that administers Synapse."
  type        = string
}

variable "enable_synapse_dedicated_pool" {
  description = "Create a dedicated SQL pool (billed while running). Serverless SQL is always available."
  type        = bool
  default     = false
}

variable "synapse_dedicated_pool_sku" {
  description = "Dedicated SQL pool performance level."
  type        = string
  default     = "DW100c"
}

variable "data_engineer_group_object_id" {
  description = "Optional Entra ID group granted read access to the lake for investigation."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Log Analytics retention in days."
  type        = number
  default     = 30
}

variable "alert_email_addresses" {
  description = "Recipients of Azure Monitor action-group alerts."
  type        = list(string)
  default     = []
}

variable "adf_git_configuration" {
  description = "Azure DevOps Git integration for the authoring (dev) factory. Leave null for higher environments, which are deployed from CI."
  type = object({
    account_name    = string
    project_name    = string
    repository_name = string
    branch_name     = string
    root_folder     = string
    tenant_id       = string
  })
  default = null
}

variable "tags" {
  description = "Additional tags merged onto every resource."
  type        = map(string)
  default     = {}
}
