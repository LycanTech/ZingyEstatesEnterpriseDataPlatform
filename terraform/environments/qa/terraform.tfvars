# Non-secret configuration for qa. Committed to source control.
# Secret or tenant-specific values are supplied by the Azure DevOps variable group
# vg-zingyestates-qa as TF_VAR_* variables:
#   TF_VAR_synapse_admin_group_object_id
#   TF_VAR_data_engineer_group_object_id   (optional)
#   TF_VAR_alert_email_addresses           (optional, JSON list)

environment = "qa"
location    = "eastus2"
name_suffix = "ze01"

vnet_address_space            = "10.40.4.0/22"
allowed_ip_ranges             = []
public_network_access_enabled = true

storage_replication_type = "LRS"
databricks_sku           = "premium"

synapse_admin_group_name      = "sg-zingyestates-qa-synapse-admins"
enable_synapse_dedicated_pool = false
synapse_dedicated_pool_sku    = "DW100c"

log_retention_days = 30
