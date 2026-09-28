# Synapse and Power BI (`SYN-*`, `PBI-*`)

Connect for investigation (after `az login`, from an allowed IP):

```bash
sqlcmd -S syn-zingy-<env>-<sfx>-ondemand.sql.azuresynapse.net -d zingy_lakehouse --authentication-method ActiveDirectoryDefault
sqlcmd -S syn-zingy-<env>-<sfx>.sql.azuresynapse.net -d dw_zingy --authentication-method ActiveDirectoryDefault
```

## SYN-01 `Login failed for user '<token-identified principal>'`

**Cause:** One of the following:
- Your IP isn't in the Synapse firewall.
- The identity isn't a database user and isn't in the Entra ID admin group `sg-zingyestates-<env>-synapse-admins`.
- You're connecting to the wrong database, for example `master` on the dedicated endpoint.

**Fix now:**

```bash
az synapse workspace firewall-rule create -g rg-zingyestates-<env>-data --workspace-name syn-zingy-<env>-<sfx> \
  --name me-temp --start-ip-address <ip> --end-ip-address <ip>
```

Add yourself to the admin group, or create a user for the identity. Remove the temporary rule afterwards.

**Prevent:** Add corporate ranges through `allowed_ip_ranges` in tfvars, not by hand.

## SYN-02 `CREATE USER ... FROM EXTERNAL PROVIDER` fails

**Symptom:** `Principal 'adf-zingy-<env>-<sfx>' could not be found or this principal type is not supported`, or `Principal ... could not be resolved`.

**Cause:** The name doesn't match the Entra display name exactly, the reporting group doesn't exist, or the identity running the script can't read the directory.

**Fix now:** Confirm the names: `az ad sp list --display-name adf-zingy-<env>-<sfx> -o table` and `az ad group show -g <reportingGroupName>`. Rerun the Synapse job. If directory lookups are blocked, grant the Synapse workspace identity the **Directory Readers** role (or add it to a group that has it).

**Prevent:** Create the Entra groups before the first deployment (see [environments.md](../environments.md#first-time-bootstrap-order)).

## SYN-03 `dw.usp_load_all` fails in COPY INTO

**Symptom:**
- `Not able to validate external location because The remote server returned an error: (403) Forbidden`
- `Cannot find the files` / `No files found`
- Column conversion errors

**Cause and fix:**
- **403:** the Synapse MI lacks Storage Blob Data Contributor, or the lake firewall trusted-instance rule for the workspace is missing. Rerun Terraform.
- **No files:** gold didn't write `_exports/<table>/run_date=<date>/`. Check that the Databricks gold task succeeded for the date and that the `run_date` values match.
- **Column errors:** gold output changed but `stg.*` didn't. Add a `V###` migration that alters or recreates the staging table in the **same column order** as `gold.py`.
```sql
SELECT TOP 20 * FROM dw.load_audit ORDER BY finished_at DESC;
```

**Prevent:** When changing `gold.py` columns, update `synapse/dedicated/migrations` in the same PR.

## SYN-04 The dedicated pool is paused and deployments or loads fail

**Symptom:** `Database 'dw_zingy' on server ... is not currently available`.

**Fix now:** `az synapse sql pool resume -g rg-zingyestates-<env>-data --workspace-name syn-zingy-<env>-<sfx> -n dw_zingy`. `scripts/deploy-synapse.sh` resumes the pool automatically for deployments.

**Prevent:** If you pause the pool to save cost, schedule a resume before 02:00 UTC.

## SYN-05 A migration failed halfway through

**Symptom:** A `V###` file failed after partly applying. The next deploy tries to rerun it and fails with `There is already an object named ...`.

**Cause:** Dedicated SQL DDL isn't transactional across `GO` batches, and the version is recorded only after the whole file succeeds.

**Fix now:** Manually finish or undo the partial objects, then record the version:

```sql
INSERT INTO dbo.schema_migrations VALUES ('V003__example', SYSUTCDATETIME());
```

**Prevent:** Keep migrations small and guard objects (`IF OBJECT_ID(...) IS NULL`).

## SYN-06 Serverless view error: `Content of directory on path ... cannot be listed` or `File ... cannot be opened`

**Cause:**
- The caller lacks `REFERENCES` on `WorkspaceIdentity`, so the reporting user isn't in `reporting_reader`.
- The workspace MI lacks storage access.
- The path is wrong (the gold table was renamed).

**Fix now:** Rerun the Synapse deploy (`004_security.sql` grants access). Check with:

```sql
SELECT TOP 5 * FROM OPENROWSET(BULK 'dim_property/', DATA_SOURCE = 'gold_lake', FORMAT = 'DELTA') AS r;
```

**Prevent:** Change `003_gold_views.sql` in the same PR whenever you add, rename, or drop gold tables.

## SYN-07 Serverless Delta view returns stale or duplicated rows

**Cause:** Serverless reads the Delta log at query time, so staleness usually means caching in the client (for example the Power BI Import model hasn't refreshed). Duplicates mean the path points at a parent folder that contains `_exports` Parquet as well as Delta.

**Fix now:** Refresh Power BI. Make sure view paths point at the table folders (`dim_property/`), not at `gold/` itself.

**Prevent:** Keep export snapshots under `_exports/`, separate from the Delta tables.

## SYN-08 The master key password is lost or needs rotation

**Fix now:** The serverless master key protects only the database-scoped credential, which uses managed identity. Rotate it with:

```sql
ALTER MASTER KEY REGENERATE WITH ENCRYPTION BY PASSWORD = '<new strong password>';
```

Then update `SYNAPSE_MASTER_KEY_PASSWORD` in the GitHub environments and the Azure DevOps variable groups.

**Prevent:** Store the value only in secret stores.

## SYN-09 Queries are slow on the dedicated pool

**Cause:** Stale statistics after CTAS swaps, a small DWU, or skewed hash distribution.

**Fix now:**

```sql
UPDATE STATISTICS dw.fact_sales;
DBCC PDW_SHOWSPACEUSED('dw.fact_sales');   -- check distribution skew
```

Scale up temporarily: `az synapse sql pool update ... --performance-level DW200c`.

**Prevent:** Add statistics updates at the end of `dw.usp_load_all`, and review distribution keys as data grows.

## SYN-10 Deploy fails at the firewall step: `curl: (6) Could not resolve host: api.ipify.org`

**Cause:** The agent couldn't discover its public IP, which the deploy script uses to open a temporary Synapse firewall rule.

**Fix now:** Rerun. If it keeps failing, replace the lookup with `curl -fsS https://ifconfig.me`.

**Prevent:** Self-hosted agents inside the VNet remove the need for temporary firewall rules.

## PBI-01 Scheduled refresh fails: credentials expired

**Fix now:** Power BI service → dataset → Settings → Data source credentials → sign in again (OAuth2).

**Prevent:** Use a service principal or a workspace identity for the dataset connection instead of a personal account.

## PBI-02 A report shows old data

**Cause:** The dataset refresh (03:30 UTC) ran before the pipeline finished, or the pipeline failed.

**Fix now:** Check ADF and Databricks for the date, then refresh the dataset manually.

**Prevent:** Trigger the Power BI refresh from ADF (a Web activity to the Power BI REST API) after `pl_load_synapse`, instead of on a fixed time.

## PBI-03 A user can't see data they should (or sees too much)

**Cause:** Row-level security role mapping (`dim_agent[office]`), or the user isn't in the reporting group, which is also needed for Synapse access.

**Fix now:** Check the role members in the Power BI service, then group membership in Entra ID.

**Prevent:** Manage access through groups only.
