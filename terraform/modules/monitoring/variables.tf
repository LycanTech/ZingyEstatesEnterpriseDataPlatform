variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "retention_days" {
  type = number
}

variable "alert_email_addresses" {
  type = list(string)
}

variable "tags" {
  type = map(string)
}
