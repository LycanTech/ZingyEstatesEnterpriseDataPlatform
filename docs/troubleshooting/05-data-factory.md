# Azure Data Factory (`ADF-*`)

Find failures fast:

```kusto
// Log Analytics workspace log-zingy-<env>
ADFActivityRun
| where TimeGenerated > ago(24h) and Status == "Failed"
| project TimeGenerated, PipelineName, ActivityName, ErrorCode, ErrorMessage
| order by TimeGenerated desc
```

```bash
az datafactory pipeline-run query-by-factory -g rg-zingyestates-<env>-data --factory-name adf-zingy-<env>-<sfx> \
  --last-updated-after $(date -u -d '-1 day' +%FT%TZ) --last-updated-before $(date -u +%FT%TZ) \
  --filters operand=Status operator=Equals values=Failed -o table
```

## ADF-01 Key Vault secret can't be read

**Symptom:** Linked service `ls_crm_sql` or `ls_listings_api` fails with a Key Vault error (secret not found, `Forbidden`, or `The user, group or application ... does not have secrets get permission`).

**Cause:** The secret was never loaded, was renamed, or was deleted. The factory identity lost **Key Vault Secrets User**. Or the `mpe-key-vault` managed private endpoint isn't approved.

**Fix now:**

```bash
az keyvault secret show --vault-name kv-zingy-<env>-<sfx> --name crm-sql-connection-string --query id
az role assignment list --scope $(az keyvault show -n kv-zingy-<env>-<sfx> --query id -o tsv) -o table
```

Reload the secret ([operations.md](../operations.md#first-deployment)), rerun the Terraform stage to restore RBAC, or approve the endpoint ([TF-14](04-terraform-and-azure.md#tf-14-managed-private-endpoints-stuck-pending)).

**Prevent:** Keep secret names fixed (`crm-sql-connection-string`, `listings-api-key`). Rotate values, not names.

## ADF-02 Copy to the lake fails with 403 / `AuthorizationFailure`

**Symptom:** `This request is not authorized to perform this operation` writing to `landing`.

**Cause:** The factory MI lost **Storage Blob Data Contributor**, `mpe-lake-dfs` is pending or rejected, or the lake firewall changed.

**Fix now:** Check ADF Studio → Manage → Managed private endpoints (must be **Approved**). Check the role on the storage account, then rerun the Terraform stage to restore it.

**Prevent:** Only Terraform manages the network rules on `azurerm_storage_account_network_rules.lake`.

## ADF-03 CRM source unreachable or login fails

**Symptom:** `Cannot connect to SQL Database`, `Login failed for user`, or a timeout on `Copy CRM table to landing`.

**Cause:** The CRM password was rotated but the Key Vault secret wasn't updated, the CRM SQL firewall blocks the ADF managed VNet, or the CRM server is down.

**Fix now:** Update the secret with the new connection string. ADF always reads the latest version, so no redeploy is needed:

```bash
az keyvault secret set --vault-name kv-zingy-<env>-<sfx> --name crm-sql-connection-string --value '<new>'
```

Test with ADF Studio → Linked services → `ls_crm_sql` → Test connection. Rerun `pl_master_daily` for the date.

**Prevent:** Coordinate credential rotation with the CRM team. Better still, switch the CRM connection to managed-identity auth.

## ADF-04 CRM table renamed or column changed

**Symptom:** `Invalid object name 'sales.Property'`, or the copy succeeds but silver rejections spike.

**Fix now:** Update `crm_tables` in `adf/pipeline/pl_ingest_crm.json` (the `tables` default value), then run `make adf-validate` and deploy. For column changes see [DATA-03](07-data-issues.md#data-03-source-schema-changed-new-renamed-or-retyped-column).

**Prevent:** Agree a data contract with the CRM team and get notice of schema changes.

## ADF-05 Listings API changed, throttles, or returns endless pages

**Symptom:** `429 Too Many Requests`, `401`, copy runs for hours, or 0 rows copied.

**Cause:**
- The API key expired.
- The rate limit was hit.
- Pagination changed (`$.paging.next` no longer present, or it never becomes empty).
- The payload moved away from `$.data`.

**Fix now:**

```bash
curl -s -H "x-api-key: $KEY" "https://api.listings-partner.example.com/v2/listings?page_size=5" | jq 'keys, .paging'
```

Update `paginationRules` or `collectionReference` in `adf/pipeline/pl_ingest_listings.json`, or raise `requestInterval` to back off. Rotate the key in Key Vault (`listings-api-key`).

**Prevent:** Put a `timeout` on the copy activity (currently 2 hours via the retry policy). Subscribe to the partner's API change notices.

## ADF-06 Pipeline did not run overnight

**Symptom:** No `pl_master_daily` run for today, and the freshness alert fires.

**Cause:** Trigger `tr_daily_0200_utc` is **Stopped**. A failed deployment can leave it stopped, because the pre-deploy script stops triggers and the post-deploy script restarts them.

**Fix now:**

```bash
az datafactory trigger show -g rg-zingyestates-<env>-data --factory-name adf-zingy-<env>-<sfx> --name tr_daily_0200_utc --query properties.runtimeState
az datafactory trigger start -g rg-zingyestates-<env>-data --factory-name adf-zingy-<env>-<sfx> --name tr_daily_0200_utc
az datafactory pipeline create-run -g rg-zingyestates-<env>-data --factory-name adf-zingy-<env>-<sfx> --name pl_master_daily --parameters '{"run_date":"YYYY-MM-DD"}'
```

**Prevent:** Rerun failed CD jobs rather than leaving them. Add a Datadog monitor on `azure.datafactory_factories.trigger_succeeded_runs` being 0 over 26 hours.

## ADF-07 `Run medallion job` fails (DatabricksJob activity)

**Symptom:** `PERMISSION_DENIED`, `Job <id> does not exist`, or `INVALID_PARAMETER_VALUE`.

**Cause:**
- The global parameter `databricks_job_id` is stale because the job was recreated with a new ID.
- The ADF managed identity lacks access to the workspace (it needs Contributor on the workspace, which Terraform grants).
- The job itself failed ([DBX-*](06-databricks-and-spark.md)).

**Fix now:**

```bash
cd databricks && databricks bundle summary -t <env> --var storage_account=<acct> -o json | jq '.resources.jobs.zingy_daily_medallion.id'
```

If the ID differs from the ADF global parameter, rerun the CD `data-factory` job (it passes the current ID), or edit the global parameter in ADF Studio as a stopgap.

**Prevent:** Don't rename the bundle job key `zingy_daily_medallion`, because renaming recreates the job with a new ID.

## ADF-08 `Load warehouse` fails

**Symptom:** The `pl_load_synapse` stored procedure fails.

**Cause:** The dedicated pool is paused, the ADF MI isn't a database user (`roles.sql` didn't run), or no exports exist for the run date.

**Fix now:**

```bash
az synapse sql pool show -g rg-zingyestates-<env>-data --workspace-name syn-zingy-<env>-<sfx> -n dw_zingy --query status
az synapse sql pool resume -g rg-zingyestates-<env>-data --workspace-name syn-zingy-<env>-<sfx> -n dw_zingy
```

Then see [SYN-03](08-synapse-and-power-bi.md#syn-03-dwusp_load_all-fails-in-copy-into) and [SYN-02](08-synapse-and-power-bi.md#syn-02-create-user--from-external-provider-fails).

**Prevent:** Don't pause the pool during the 02:00–04:00 UTC load window.

## ADF-09 Integration runtime is slow to start, or copies queue

**Symptom:** Activities sit "Queued" for minutes, or show long queue times.

**Cause:** The managed-VNet IR has a cold start (TTL 10 min), or too many parallel copies.

**Fix now:** Normally nothing: it warms after the first activity. For large backfills, raise `timeToLive` in `adf/integrationRuntime/ir-managed-vnet.json` temporarily.

**Prevent:** Keep `batchCount` in `pl_ingest_crm` modest (it's 4).

## ADF-10 ARM deployment fails: `The template parameter '...' is not found`

**Symptom:** CD `data-factory` fails at the ARM deploy step.

**Cause:** A parameter override in `deploy-environment.yml` / `adf-deploy.yml` no longer exists in the exported template. This happens after renaming a linked service or editing `arm-template-parameters-definition.json`.

**Fix now:** Export locally and list the real parameter names:

```bash
make adf-export && python -c "import json;print(list(json.load(open('adf/ArmTemplate/ARMTemplateParametersForFactory.json'))['parameters']))"
```

Update the overrides in **both** CI/CD systems.

**Prevent:** Treat linked service names as an API. Change them together with the pipeline overrides.

## ADF-11 Deployment leaves deleted pipelines behind, or fails deleting them

**Cause:** Incremental ARM deployment doesn't delete removed resources. The post-deploy script (`-deleteDeployment $true`) cleans up, but it runs only if the deployment succeeded.

**Fix now:** Rerun the `data-factory` job, or delete the orphan in ADF Studio.

**Prevent:** Don't cancel CD during the ADF step.

## ADF-12 Dev factory changes made in ADF Studio are lost

**Cause:** Higher environments are deployed from Git. In dev, an ARM deploy from CI overwrites Studio edits that weren't committed.

**Fix now:** Recover from the Studio's Git branch if Git integration is on. Otherwise, redo the change as JSON in `adf/`.

**Prevent:** Enable `adf_git_configuration` for dev so Studio saves to Git. Never author in qa, uat or prod.

## ADF-13 Duplicate data after a rerun

**Symptom:** Landing contains more than one file set for a date.

**Cause:** The copy sink writes new file names, so a rerun adds files instead of replacing them.

**Fix now:** Bronze replaces the whole run-date partition and silver deduplicates by key, so the outputs are still correct. To clean up landing:

```bash
az storage fs directory delete -f landing -n "crm/<entity>/ingest_date=<date>" --account-name <acct> --auth-mode login --yes
```

Then rerun the day.

**Prevent:** Optionally add a Delete activity for the date folder before each copy.
