# Security and secrets (`SEC-*`)

Where each secret lives: see the README section [Secrets and sensitive values](../../README.md#secrets-and-sensitive-values).

## SEC-01 A secret was committed or pushed

This repository is **public**. Treat any pushed secret as compromised, even if you delete the commit straight away.

**Fix now, in this order:**
1. **Revoke or rotate the secret first**, at its source (Datadog, Azure app registration, Key Vault, CRM). Deleting the commit doesn't make the secret safe.
2. Update the new value where it's stored (GitHub environment secrets, Azure DevOps variable group, Key Vault).
3. Remove it from history:
   ```bash
   pip install git-filter-repo
   git filter-repo --replace-text <(echo '<the-secret>==>REDACTED')
   git push --force-with-lease origin main
   ```
   Everyone must re-clone afterwards. Ask GitHub Support to purge cached views if needed.
4. Check the provider's audit logs for use of the leaked secret.

**Prevent:** Gitleaks runs in pre-commit and CI. Keep real values only in git-ignored files (`.env`, `.github/env/*.env`).

## SEC-02 A secret was printed in a workflow log

**Symptom:** A value appears unmasked in GitHub Actions or Azure DevOps logs (public for GitHub).

**Cause:** The value wasn't registered as a secret (for example it came from a variable, or was derived or transformed). Or someone used `set -x` or `echo` on it.

**Fix now:** Rotate the value (SEC-01). Delete the run's logs: `gh run delete <run-id>`, or Actions UI → run → Delete all logs.

**Prevent:** Store sensitive values only as **secrets**, never as variables. Mask derived values (`echo "::add-mask::$VALUE"`). Never pass secrets as command arguments (the repo already uses stdin and environment variables).

## SEC-03 Rotating the Datadog API and application keys

**Fix now:**
1. Create new keys in Datadog.
2. Update the secrets in every place:
   ```bash
   for e in dev qa uat prod; do for s in "$e" "$e-automation"; do
     gh secret set DD_API_KEY --env "$s" --body "$NEW_API_KEY"
     gh secret set DD_APP_KEY --env "$s" --body "$NEW_APP_KEY"
   done; done
   ```
   Also update the Azure DevOps variable groups.
3. Run CD for each environment. The Databricks step rewrites the `zingy-platform/datadog-api-key` secret.
4. Revoke the old keys.

**Prevent:** Rotate on a schedule ([AGE-07](12-aging-and-maintenance.md#age-07-credentials-with-an-expiry-date)).

## SEC-04 Datadog Azure integration secret expires

**Symptom:** Azure metrics stop arriving ([MON-02](09-monitoring-datadog.md#mon-02-azure-metrics-adf-storage-missing-in-datadog)), and the Datadog Azure tile shows an authentication error.

**Fix now:**

```bash
az ad app credential reset --id <datadog-app-client-id> --display-name datadog --years 1 --append --query password -o tsv
gh secret set DATADOG_AZURE_CLIENT_SECRET --env <env> --body '<new>'            # and <env>-automation
```

Run CD (Terraform updates `datadog_integration_azure`), then remove the old credential with `az ad app credential delete --id <app> --key-id <old-key-id>`.

**Prevent:** Put a calendar reminder 30 days before `endDateTime`.

## SEC-05 CRM or listings credentials rotated by the source team

**Fix now:** Update the Key Vault secret. ADF always reads the latest version:

```bash
az keyvault secret set --vault-name kv-zingy-<env>-<sfx> --name listings-api-key --value '<new>'
```

Rerun failed runs.

**Prevent:** Agree a rotation procedure with the source owners. Set `--expires` on the secrets so Key Vault's near-expiry events can alert.

## SEC-06 Someone was granted too much access, or a leaver still has access

**Fix now:**

```bash
az role assignment list --all --assignee <user-or-sp> -o table
az role assignment delete --assignee <user-or-sp> --scope <scope> --role <role>
```

Remove them from the Entra groups (Synapse admins, reporting), Databricks workspace users, GitHub environment reviewers and the Azure DevOps project.

**Prevent:** Grant access through groups only. Run quarterly access reviews.

## SEC-07 Dependabot or GitHub security alert on a dependency

**Fix now:** Security tab → the alert. Merge the Dependabot security PR once CI is green. For `pyspark`/`delta-spark` (ignored by Dependabot), assess the fix against the Databricks runtime ([AGE-01](12-aging-and-maintenance.md#age-01-databricks-runtime-154-lts-reaches-end-of-support)).

**Prevent:** Enable Dependabot security alerts and secret scanning (Settings → Code security).

## SEC-08 GitHub Action supply-chain concern (compromised third-party action)

**Fix now:** Pin the affected action to a known-good **commit SHA** instead of a tag, and check recent runs for unexpected behaviour. Rotate any secrets that jobs using the action could reach.

**Prevent:** Allow only trusted actions (Settings → Actions → Allow select actions). Consider pinning every `uses:` to a SHA; Dependabot still updates SHA pins.

## SEC-09 Public network exposure flagged by an audit

**Symptom:** Security review flags that storage, Key Vault, ADF or Synapse are reachable publicly.

**Cause:** `public_network_access_enabled = true`, kept deliberately so Microsoft-hosted agents can deploy (firewalled, default deny).

**Fix now:** For uat and prod, set up self-hosted agents in the VNet, then set `public_network_access_enabled = false` in tfvars and remove the matching exceptions from `.checkov.yml`.

**Prevent:** Track this as a known risk in [security.md](../security.md).

## SEC-10 Suspicious data access in the lake

**Fix now:** Query the storage logs in Log Analytics:

```kusto
StorageBlobLogs
| where TimeGenerated > ago(7d) and AccountName == "<acct>"
| summarize count() by RequesterObjectId, OperationName, CallerIpAddress
| order by count_ desc
```

Disable the principal, rotate its credentials, and preserve the logs.

**Prevent:** Keep storage diagnostics on (`modules/diagnostics`). Consider Microsoft Defender for Storage.
