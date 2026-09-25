variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "storage_account_id" {
  type = string
}

variable "key_vault_id" {
  type = string
}

variable "git_configuration" {
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
  type = map(string)
}
