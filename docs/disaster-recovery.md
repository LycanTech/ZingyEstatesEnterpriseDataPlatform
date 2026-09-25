# Disaster recovery

## Targets (prod)

| | RPO | RTO |
|---|---|---|
| Lake data (bronze, silver, gold) | ≤ 15 min (RA-GZRS async replication) | 8 h |
| Infrastructure | 0 (all in Terraform) | 4 h to redeploy |
| Warehouse (dedicated pool) | 24 h (geo-backup) | 8 h |
| Pipelines, jobs, SQL | 0 (all in Git) | redeploy with CI |

## What protects what

| Failure | Protection | Recovery |
|---|---|---|
| Bad transformation overwrote a table | Delta time travel | `RESTORE TABLE delta.\`<path>\` TO VERSION AS OF <n>` |
| Deleted blobs or containers | Soft delete (14 days) | `az storage blob undelete` / restore container |
| Bad source extract | Bronze keeps each run date | Fix the source, then rerun the day (see [operations.md](operations.md#rerunning-a-day)) |
| Region outage | RA-GZRS lake in prod, geo-backup for the dedicated pool | See the procedure below |
| Deleted Key Vault | Soft delete (90 days) + purge protection | `az keyvault recover` |
| Lost Terraform state | Versioned, soft-deleted, delete-locked state account | Restore a previous blob version |

## Regional failover procedure (prod)

1. Declare the incident and pause the ADF trigger in the primary region if it's reachable.
2. Initiate storage account failover: `az storage account failover --name <account>`. The secondary becomes the primary, as LRS.
3. In `terraform/environments/prod/terraform.tfvars`, set `location` to the paired region and choose a new `vnet_address_space`. Then run the prod stage. This recreates compute (Databricks, ADF, Synapse, Key Vault) and points it at the failed-over lake.
4. Restore the dedicated pool from geo-backup into the new workspace.
5. Reload Key Vault secrets (see operations.md) and approve the managed private endpoints.
6. Run `pl_master_daily` for each missed date.
7. Afterwards, re-enable geo-replication on the storage account.

Test this procedure in UAT at least once a year and record the RTO you actually achieved.
