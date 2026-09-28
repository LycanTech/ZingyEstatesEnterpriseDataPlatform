# CD and deployments (`CD-*`)

Setup references: [cicd-github-actions.md](../cicd-github-actions.md) (GitHub) and [environments.md](../environments.md) (Azure DevOps).

## CD-01 CD workflow is skipped

**Symptom:** The CD run completes in a few seconds with every job skipped.

**Cause:** One of the following:
1. The repository variable `DEPLOY_ENABLED` isn't `true`.
2. CI was triggered by a pull request, not a push (CD deploys only pushed commits).
3. The branch isn't `main` or `develop`.
4. CI failed.

**Fix now:**

```bash
gh variable list                                   # is DEPLOY_ENABLED=true?
gh variable set DEPLOY_ENABLED --body true
gh workflow run cd.yml -f environment=dev          # deploy manually
```

**Prevent:** This is intended behaviour until setup is finished.

## CD-02 `AADSTS700213: No matching federated identity record found`

**Symptom:** `azure/login` or Terraform fails with `No matching federated identity record found for presented assertion subject 'repo:LycanTech/ZingyEstatesEnterpriseDataPlatform:environment:qa-automation'`.

**Cause:** The Azure app registration has no federated credential for that exact subject. Every job environment (`<env>` **and** `<env>-automation`) needs one. Subjects are case-sensitive and include the repo name, so renaming or transferring the repo breaks them.

**Fix now:**

```bash
az ad app federated-credential list --id <AZURE_CLIENT_ID> --query "[].subject" -o tsv
az ad app federated-credential create --id <AZURE_CLIENT_ID> --parameters '{
  "name": "github-qa-automation",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:LycanTech/ZingyEstatesEnterpriseDataPlatform:environment:qa-automation",
  "audiences": ["api://AzureADTokenExchange"]}'
```

**Prevent:** Use `scripts/setup-github-environments.sh`, which prints the exact commands. Update the subjects if the repo is renamed or transferred.

## CD-03 `AADSTS7000215` / `AADSTS700016`: application not found or invalid

**Symptom:** Login fails and names the client ID.

**Cause:** `AZURE_CLIENT_ID` or `AZURE_TENANT_ID` in the GitHub environment is wrong, or the app registration was deleted.

**Fix now:** `gh variable list --env <env>`, then compare against `az ad app show --id <client-id>`. Fix it with `gh variable set AZURE_CLIENT_ID --env <env> --body <id>`, in both `<env>` and `<env>-automation`.

**Prevent:** Load both environments from the same values file.

## CD-04 Authorization failed during `terraform apply` (`does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/write'`)

**Cause:** The deploying identity has Contributor but not User Access Administrator or Owner. Terraform creates role assignments.

**Fix now:**

```bash
az role assignment create --assignee <client-id> --role "User Access Administrator" --scope /subscriptions/<sub-id>
```

(Or use Role Based Access Control Administrator with a condition that limits which roles it can assign.)

**Prevent:** Document the required roles in the environment onboarding checklist ([environments.md](../environments.md)).

## CD-05 Terraform backend: `403 ... AuthorizationPermissionMismatch` on the state blob

**Cause:** The identity lacks **Storage Blob Data Contributor** on `stzingytfstate` / `tfstate-<env>`. `use_azuread_auth = true` means data-plane RBAC is required, not account keys.

**Fix now:**

```bash
SA_ID=$(az storage account show -n stzingytfstate -g rg-zingyestates-tfstate --query id -o tsv)
az role assignment create --assignee <client-id> --role "Storage Blob Data Contributor" --scope "$SA_ID/blobServices/default/containers/tfstate-<env>"
```

RBAC can take a few minutes to propagate. Then rerun.

**Prevent:** Part of the bootstrap output from `scripts/bootstrap-tfstate.sh`.

## CD-06 Deployment is waiting for approval forever

**Symptom:** The `infrastructure` job shows "Waiting for review".

**Cause:** uat and prod need a reviewer. The reviewer may be away, or be the person who triggered the run, if "prevent self-review" is on.

**Fix now:** A reviewer approves in the run page, or runs `gh run view <id> --web`. To change reviewers: Settings → Environments → `<env>`.

**Prevent:** Configure at least two reviewers for uat and prod.

## CD-07 Plan looks fine but apply does something different

**Cause:** The GitHub apply job **re-plans** (plans aren't passed between jobs because the repo is public). Something changed between plan and apply, such as manual portal edits or another run.

**Fix now:** Cancel the run. Investigate drift ([TF-02](04-terraform-and-azure.md#tf-02-drift-someone-changed-resources-in-the-portal)), then rerun.

**Prevent:** No manual changes in the portal. Keep CD concurrency (`cd-<branch>`) so only one deployment per branch runs at a time.

## CD-08 Azure DevOps: `AADSTS700024: Client assertion is not within its valid time range`

**Symptom:** Long Terraform applies fail partway through, often at the Synapse or Databricks step.

**Cause:** The Azure DevOps `idToken` exposed through `AzureCLI@2` is short-lived, and `pipelines/scripts/arm-env.sh` passes it to Terraform as a static `ARM_OIDC_TOKEN`.

**Fix now:** Rerun the stage. Terraform resumes from state.

**Prevent:** Use azurerm's built-in refresh for Azure DevOps (azurerm ≥ 4 and a recent Terraform). Set these on the Terraform steps instead of `ARM_OIDC_TOKEN`:

```yaml
env:
  ARM_USE_OIDC: "true"
  ARM_ADO_PIPELINE_SERVICE_CONNECTION_ID: <service-connection-id>   # alias: ARM_OIDC_AZURE_SERVICE_CONNECTION_ID
  ARM_OIDC_REQUEST_TOKEN: $(System.AccessToken)
  ARM_CLIENT_ID: <client-id>
  ARM_TENANT_ID: <tenant-id>
```

Or split long applies with `-target` only as a one-off.

## CD-09 Azure DevOps: Terraform receives a literal `$(synapseAdminGroupObjectId)`

**Symptom:** `expected "synapse_admin_group_object_id" to be a valid UUID, got $(synapseAdminGroupObjectId)`.

**Cause:** The variable is missing from `vg-zingyestates-<env>`, and Azure DevOps leaves undefined macros as literal text.

**Fix now:** Add the variable to the group, and make sure the pipeline has permission to use the group (Library → group → Pipeline permissions).

**Prevent:** Follow the variable table in [environments.md](../environments.md).

## CD-10 Azure DevOps: `The pipeline is not valid. Could not find service connection sc-zingyestates-<env>`

**Cause:** The service connection is missing, named differently, or not authorised for this pipeline.

**Fix now:** Project settings → Service connections → create it or rename it to `sc-zingyestates-<env>`, and grant pipeline permission.

**Prevent:** Keep the names exactly as the templates expect.

## CD-11 Manual `workflow_dispatch` to prod is skipped

**Cause:** By design, `cd.yml` deploys prod manually only from `main`.

**Fix now:** Run from main: `gh workflow run cd.yml --ref main -f environment=prod`.

**Prevent:** This is intended.

## CD-12 Changes to `cd.yml` on a branch have no effect

**Cause:** `workflow_run` workflows always run the version of the file on the **default branch**.

**Fix now:** Merge the workflow change to `main` first, or test with `workflow_dispatch` on the branch.

**Prevent:** Test CD changes with manual dispatch against dev.

## CD-13 A partial deployment leaves environments inconsistent

**Symptom:** Infrastructure applied, but the Databricks, ADF or Synapse job failed.

**Fix now:** Fix the cause and rerun the failed jobs only: `gh run rerun <id> --failed`. Every step is idempotent (Terraform, bundle deploy, incremental ARM, versioned migrations plus repeatable SQL).

**Prevent:** Watch the smoke test in qa and uat. It catches most integration breaks before prod.

## CD-14 Smoke test times out

**Symptom:** `scripts/smoke-test-adf.sh` prints `Timed out after 90 minutes`.

**Cause:** A cold cluster start plus big data volumes, a stuck copy activity, or a paused dedicated pool.

**Fix now:** Check ADF Monitor for the run. Raise `TIMEOUT_MINUTES` for that run if it's only slow.

**Prevent:** Keep QA data volumes small (masked subset).

## CD-15 Rollback needed after a bad release

**Fix now:**
- **Code, jobs, ADF, SQL:** revert the commit on `main` (`git revert <sha> && git push`). CD redeploys the previous state through qa, uat and prod. For urgent prod fixes, dispatch prod after qa passes.
- **Data:** restore Delta tables to the previous version ([DBX-10](06-databricks-and-spark.md#dbx-10-bad-data-written-restore-a-delta-table)).
- **Synapse migrations** are forward-only. Write a new `V###` that undoes the change.

**Prevent:** Small releases and the uat approval gate.
