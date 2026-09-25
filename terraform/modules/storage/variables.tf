variable "name" {
  description = "Storage account name (3-24 lowercase alphanumeric, globally unique)."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "replication_type" {
  type = string
}

variable "public_network_access_enabled" {
  type = bool
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
