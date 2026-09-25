# Environments

| | local | dev | qa | uat | prod |
|---|---|---|---|---|---|
| Purpose | Laptop demo and tests | Integration of `develop` | Automated end-to-end testing | Business sign-off, prod-like | Production |
| Deployed from | `docker compose` | `develop` branch | `main` branch | `main`, after QA | `main`, after UAT |
| Approval | none | none | none | required | required (2 approvers) |
| Smoke test (runs `pl_master_daily`) | n/a | no | yes | yes | no |
| Compute | Spark in Docker | DBR 15.4, 1–2 workers | 1–2 workers | 1–4 workers | 1–8 workers |
| Lake replication | local disk | LRS | LRS | ZRS | RA-GZRS |
| Synapse dedicated pool | n/a | off | off | DW100c | DW200c |
| Log retention | n/a | 30 d | 30 d | 60 d | 90 d |
| VNet | n/a | 10.40.0.0/22 | 10.40.4.0/22 | 10.40.8.0/22 | 10.40.12.0/22 |
| Data | synthetic (`sample_data.py`) | synthetic or masked | masked | masked copy of prod | real |

Configuration per environment:

- `terraform/environments/<env>/terraform.tfvars`: non-secret sizing and network settings.
- `terraform/environments/<env>/backend.hcl`: remote state location.
- `datadog/environments/<env>.tfvars` and `<env>.backend.hcl`: alert routing and state.
- `databricks/databricks.yml` `targets.<env>`: cluster sizing and bundle mode.

## Promotion flow

```
feature/* ──PR──▶ develop ──push──▶ CI ──▶ DEV
                     │
                     └──PR──▶ main ──push──▶ CI ──▶ QA ──▶ UAT (approve) ──▶ PROD (approve)
```

Each deploy stage (`pipelines/stages/deploy-environment.yml`) runs:

1. **Plan**: Terraform plans for Azure and Datadog, published as artifacts along with a readable copy for reviewers.
2. **Infrastructure**: the approval gate, then applies exactly the reviewed plans.
3. **Databricks**: builds the wheel, sets up Unity Catalog locations, and deploys the bundle. Outputs the job ID.
4. **Data Factory**: stops triggers, deploys the ARM template with environment overrides, and restarts triggers.
5. **Synapse**: runs serverless views and security, plus dedicated migrations and procedures when the pool is enabled.
6. **Smoke test** (qa/uat): triggers `pl_master_daily` and waits for success.

## Azure DevOps setup (one time per environment)

| Item | Name | Notes |
|---|---|---|
| Service connection | `sc-zingyestates-<env>` | Azure Resource Manager with workload identity federation. Scoped to the env subscription. Needs **Owner** or **Contributor + User Access Administrator**, because Terraform creates role assignments. Also needs **Storage Blob Data Contributor** on `tfstate-<env>`. |
| Environment | `zingyestates-<env>` | Add approvals and checks for uat and prod, plus a branch control that allows only `refs/heads/main`. |
| Variable group | `vg-zingyestates-<env>` | See the variables below. Link secrets to Key Vault where possible. |

Variable group `vg-zingyestates-<env>`:

| Variable | Secret | Used by |
|---|---|---|
| `synapseAdminGroupObjectId` | no | Terraform (Synapse Entra ID admin) |
| `reportingGroupName` | no | Synapse security scripts (Power BI readers) |
| `synapseMasterKeyPassword` | yes | Serverless database master key |
| `datadogAzureTenantId` | no | Datadog Azure integration |
| `datadogAzureClientId` | no | Datadog Azure integration |
| `datadogAzureClientSecret` | yes | Datadog Azure integration |
| `DD_API_KEY` | yes | Datadog provider, job-cluster metrics |
| `DD_APP_KEY` | yes | Datadog provider |

## First-time bootstrap order

1. `scripts/bootstrap-tfstate.sh` in the management subscription.
2. Create the Entra ID groups: `sg-zingyestates-<env>-synapse-admins` and the reporting group.
3. Create the service connections, environments, and variable groups listed above.
4. Set `name_suffix` in each `terraform.tfvars` to a value that is free globally.
5. Push to `develop` to deploy dev.
6. Do the post-deploy steps in [operations.md](operations.md#first-deployment): approve private endpoints and load Key Vault secrets.
