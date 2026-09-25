variable "datadog_api_url" {
  type    = string
  default = "https://api.datadoghq.com/"
}
variable "azure_tenant_id" { type = string }
variable "azure_client_id" { type = string }
variable "azure_client_secret" {
  description = "Secret of the Datadog app registration. Supplied as TF_VAR_azure_client_secret from the Azure DevOps variable group; never committed."
  type        = string
  sensitive   = true
}
variable "environment" {
  type    = string
  default = "prod"
}
variable "company" {
  type    = string
  default = "zingyestates"
}
variable "notification_handle" {
  type    = string
  default = "@teams-zingyestates"
}
