variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "address_space" {
  description = "VNet CIDR, /22 or larger. Split into a /26 for private endpoints and two /24s for Databricks."
  type        = string
}

variable "tags" {
  type = map(string)
}
