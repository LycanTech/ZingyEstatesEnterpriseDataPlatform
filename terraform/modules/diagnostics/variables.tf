variable "log_analytics_workspace_id" {
  type = string
}

variable "target_resource_ids" {
  description = "Map of a stable key to the resource ID that should send diagnostics. Keys must be known at plan time."
  type        = map(string)
}
