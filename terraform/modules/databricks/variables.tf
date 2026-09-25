variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "sku" {
  type = string
}

variable "virtual_network_id" {
  type = string
}

variable "host_subnet_name" {
  type = string
}

variable "container_subnet_name" {
  type = string
}

variable "host_subnet_nsg_association_id" {
  type = string
}

variable "container_subnet_nsg_association_id" {
  type = string
}

variable "tags" {
  type = map(string)
}
