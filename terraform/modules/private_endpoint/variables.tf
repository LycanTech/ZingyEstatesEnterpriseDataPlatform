variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "resource_id" {
  description = "ID of the resource the endpoint connects to."
  type        = string
}

variable "subresource_name" {
  description = "Private-link sub-resource, for example blob, dfs, vault, Sql, Dev."
  type        = string
}

variable "private_dns_zone_id" {
  type = string
}

variable "tags" {
  type = map(string)
}
