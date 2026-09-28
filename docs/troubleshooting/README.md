# Troubleshooting

Scenarios that can affect this platform over time, with immediate fixes. Each entry follows the same shape:

- **Symptom:** what you see, with the exact error text where there is one. Search this folder for the error string.
- **Cause:** why it happens.
- **Fix now:** commands to resolve it.
- **Prevent:** what stops it coming back.

Scenario IDs (for example `CI-04`) are stable, so you can cite them in incidents and PRs.

| File | Covers |
|---|---|
| [01-local-development.md](01-local-development.md) | Docker, Spark, Java, Windows/OneDrive, line endings, notebooks (`LD-*`) |
| [02-ci-github-actions.md](02-ci-github-actions.md) | CI failures, Dependabot, pushing, workflow behaviour (`CI-*`) |
| [03-cd-deployments.md](03-cd-deployments.md) | GitHub CD and Azure DevOps deployments, OIDC, approvals (`CD-*`) |
| [04-terraform-and-azure.md](04-terraform-and-azure.md) | State, naming, quotas, RBAC, networking, provider upgrades (`TF-*`) |
| [05-data-factory.md](05-data-factory.md) | Ingestion, linked services, triggers, ARM deployment (`ADF-*`) |
| [06-databricks-and-spark.md](06-databricks-and-spark.md) | Jobs, Unity Catalog, bundles, Delta, performance (`DBX-*`) |
| [07-data-issues.md](07-data-issues.md) | Data quality, schema drift, late or missing data, backfills, deletes (`DATA-*`) |
| [08-synapse-and-power-bi.md](08-synapse-and-power-bi.md) | SQL deploys, COPY INTO, serverless views, reporting (`SYN-*`, `PBI-*`) |
| [09-monitoring-datadog.md](09-monitoring-datadog.md) | Missing metrics, noisy or silent monitors, SLOs (`MON-*`) |
| [10-security-and-secrets.md](10-security-and-secrets.md) | Leaks, rotation, expiry, access (`SEC-*`) |
| [11-cost-and-capacity.md](11-cost-and-capacity.md) | Spend spikes, growth, quotas (`COST-*`) |
| [12-aging-and-maintenance.md](12-aging-and-maintenance.md) | Things that break with time: EOL runtimes, deprecations, expiring credentials (`AGE-*`) |

## Quick lookup by symptom

| You see | Go to |
|---|---|
| `bash\r: No such file or directory` | [LD-05](01-local-development.md#ld-05-shell-scripts-fail-with-bashr-no-such-file-or-directory) |
| `JAVA_GATEWAY_EXITED` / Java not found | [LD-03](01-local-development.md#ld-03-java_gateway_exited-or-java-not-found-running-pytest-natively) |
| README or another file shows as binary on GitHub | [LD-06](01-local-development.md#ld-06-a-file-shows-as-binary-on-github-or-contains-null-bytes) |
| `locked provider ... does not match configured version constraint` | [CI-03](02-ci-github-actions.md#ci-03-terraform-init-fails-locked-provider--does-not-match-configured-version-constraint) |
| `refusing to allow an OAuth App to create or update workflow` | [CI-10](02-ci-github-actions.md#ci-10-push-rejected-refusing-to-allow-an-oauth-app-to-create-or-update-workflow) |
| CD run shows **skipped** | [CD-01](03-cd-deployments.md#cd-01-cd-workflow-is-skipped) |
| `AADSTS700213: No matching federated identity record` | [CD-02](03-cd-deployments.md#cd-02-aadsts700213-no-matching-federated-identity-record-found) |
| `AADSTS700024: Client assertion is not within its valid time range` | [CD-08](03-cd-deployments.md#cd-08-azure-devops-aadsts700024-client-assertion-is-not-within-its-valid-time-range) |
| `Error acquiring the state lock` | [TF-01](04-terraform-and-azure.md#tf-01-error-acquiring-the-state-lock) |
| `StorageAccountAlreadyTaken` / `VaultAlreadyExists` | [TF-03](04-terraform-and-azure.md#tf-03-storageaccountalreadytaken-or-name-not-available), [TF-04](04-terraform-and-azure.md#tf-04-key-vault-name-exists-in-deleted-state) |
| `RoleAssignmentExists` | [TF-06](04-terraform-and-azure.md#tf-06-roleassignmentexists) |
| ADF copy fails with 403 / `This request is not authorized` | [ADF-02](05-data-factory.md#adf-02-copy-to-the-lake-fails-with-403--authorizationfailure) |
| Pipeline never ran overnight | [ADF-06](05-data-factory.md#adf-06-pipeline-did-not-run-overnight) |
| Databricks `PERMISSION_DENIED` on `abfss://` | [DBX-01](06-databricks-and-spark.md#dbx-01-permission_denied-or-403-reading-abfss-paths) |
| `QuotaExceeded` / cluster fails to start | [DBX-03](06-databricks-and-spark.md#dbx-03-cluster-fails-to-start-quotaexceeded--cloud_provider_launch_failure) |
| Rejection-rate alert | [DATA-01](07-data-issues.md#data-01-rejection-rate-alert-fires) |
| Rows deleted at source still appear in reports | [DATA-07](07-data-issues.md#data-07-records-deleted-in-the-source-still-appear-in-reports) |
| `Login failed for user '<token-identified principal>'` | [SYN-01](08-synapse-and-power-bi.md#syn-01-login-failed-for-user-token-identified-principal) |
| Datadog dashboard empty | [MON-01](09-monitoring-datadog.md#mon-01-dashboard-shows-no-zingyestates-metrics) |
| A secret was committed | [SEC-01](10-security-and-secrets.md#sec-01-a-secret-was-committed-or-pushed) |
| Bill jumped | [COST-01](11-cost-and-capacity.md#cost-01-synapse-dedicated-pool-left-running) |

## General first steps for any incident

1. **Identify scope:** which environment (`dev`/`qa`/`uat`/`prod`), which run date, which component.
2. **Get the failing log:** `gh run view <run-id> --log-failed`, ADF Monitor, Databricks run output, or Log Analytics (`log-zingy-<env>`).
3. **Check what changed recently:** `git log --since="3 days ago" --oneline`, merged Dependabot PRs, Azure Service Health, and credential expiry ([AGE-*](12-aging-and-maintenance.md)).
4. **Fix, then rerun safely.** Every data step is idempotent per run date ([operations.md](../operations.md#rerunning-a-day)).
5. **Record it.** If the scenario isn't in this folder, add it (see below).

## Adding a scenario

Add it to the matching file with the next free ID, use the same four headings, and add a row to the quick lookup above if the error text is distinctive. Include exact error strings so people can search for them.
