# Security

## Identity and access

| Principal | Access | Where |
|---|---|---|
| ADF managed identity | Storage Blob Data Contributor (lake), Key Vault Secrets User, Contributor on the Databricks workspace, `etl_loader` role in Synapse | `terraform/main.tf`, `synapse/dedicated/security/roles.sql` |
| Databricks access connector | Storage Blob Data Contributor (lake), used by the Unity Catalog storage credential | `terraform/main.tf`, `scripts/setup-unity-catalog.sh` |
| Synapse managed identity | Storage Blob Data Contributor (lake), used for `COPY INTO` and serverless reads | `terraform/main.tf` |
| Deployment service principal | Subscription Owner (or Contributor + UAA), Databricks workspace admin, UC external locations READ/WRITE FILES | Azure DevOps service connection |
| `sg-zingyestates-<env>-synapse-admins` | Synapse Entra ID admin | `synapse_admin_group_*` |
| Reporting group | `reporting_reader`: SELECT on `gold` / `dw` | Synapse security scripts |
| Data engineers (optional) | Storage Blob Data Reader | `data_engineer_group_object_id` |

The platform doesn't use storage account keys or SAS tokens. `shared_access_key_enabled = false` on the lake, and the provider uses Entra ID for data-plane calls. Synapse uses **Entra-only authentication** (`azuread_authentication_only = true`).

## Secrets

- Source credentials (`crm-sql-connection-string`, `listings-api-key`) live in Key Vault. ADF reads them through `ls_keyvault`. Terraform never stores them.
- The Datadog key for job clusters is stored in the Databricks secret scope `zingy-platform`, loaded by CI from the variable group.
- Pipeline secrets live in variable groups marked secret (link them to Key Vault in production). They're mapped into tasks explicitly.
- Gitleaks runs in pre-commit and CI. `.gitignore` excludes `.env`, state, and plans.
- Secrets never go on a command line: the Datadog key is piped to the Databricks CLI via stdin, and `sqlcmd` reads the Synapse master key password from an environment variable.
- Terraform plan files are never uploaded as artifacts (the repository is public). Reviewers read the redacted plan in the CD job summary.

## Network

- Private endpoints: lake (blob and dfs), Key Vault, and Synapse (Sql, SqlOnDemand, Dev), with private DNS zones linked to the VNet.
- Databricks: VNet injection with secure cluster connectivity (`no_public_ip = true`).
- ADF: managed-VNet integration runtime with managed private endpoints to the lake and Key Vault.
- Lake firewall: `Deny` by default, with trusted resource-instance rules for the Synapse workspace and Databricks access connector.
- `public_network_access_enabled` stays on, but firewalled, until self-hosted build agents run inside the VNet. After that, set it to `false` in uat and prod.

## Data protection

- TLS 1.2 minimum, infrastructure (double) encryption, blob and container soft delete (14 days), Key Vault purge protection.
- Delta time travel on bronze, silver, and gold covers point-in-time recovery of table data.
- Quarantine data expires after 180 days and landing data after 400 days (lifecycle policy).

## Scanning and review

- Checkov scans Terraform on every CI run. Every accepted exception is listed with its reason in `.checkov.yml`.
- TFLint with the azurerm ruleset.
- UAT and prod require approval, and reviewers see the readable Terraform plan artifact before they approve.
