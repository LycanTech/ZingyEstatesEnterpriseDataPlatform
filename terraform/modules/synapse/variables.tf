variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "storage_account_name" {
  type = string
}

variable "storage_filesystem_name" {
  type = string
}

variable "admin_group_name" {
  type = string
}

variable "admin_group_object_id" {
  type = string
}

variable "enable_dedicated_pool" {
  type = bool
}

variable "dedicated_pool_sku" {
  type = string
}

variable "storage_replication_type" {
  description = "Lake replication type; GRS variants also turn on geo-backup for the dedicated pool."
  type        = string
}

variable "allowed_ip_ranges" {
  type = list(string)
}

variable "private_endpoint_subnet_id" {
  type = string
}

variable "private_dns_zone_ids" {
  type = map(string)
}

variable "tags" {
  type = map(string)
}
