# Aging and maintenance (`AGE-*`)

Things that break **with time**, even when nobody changes the code. The calendar at the end turns them into routine checks.

## AGE-01 Databricks Runtime 15.4 LTS reaches end of support

**Symptom:** Databricks warns about deprecation. Later, clusters on `15.4.x-scala2.12` can't be created.

**Fix now:** Upgrade **as a set** in one PR:
1. `spark_version` in `databricks/resources/zingy_daily_medallion.job.yml` (the next LTS).
2. `pyspark` and `delta-spark` in `requirements-dev.txt`, matching that runtime's Spark and Delta versions (the Databricks runtime release notes list them).
3. The Python version in the Dockerfile, `PYTHON_VERSION` in the workflows, and `pythonVersion` in the Azure DevOps variables, matching the runtime's Python.
4. Rebuild the local image and run the full tests (`make test-docker`). Watch for ANSI-mode and behaviour changes ([DBX-14](06-databricks-and-spark.md#dbx-14-behaviour-changes-after-a-databricks-runtime-upgrade)).
5. Deploy to dev, then compare a week of row counts and DQ metrics before promoting.

**Prevent:** Check the Databricks runtime support lifecycle quarterly.

## AGE-02 Python version reaches end of life

**Symptom:** Python 3.11 is EOL (October 2027), and libraries drop support for it.

**Fix now:** Move with the Databricks runtime (AGE-01). Local, CI and runtime must use the same Python version.

**Prevent:** Tie Python upgrades to runtime upgrades.

## AGE-03 Node.js version deprecated in Actions or the ADF utility

**Symptom:** `Node.js 20 is deprecated` warnings, or the ADF utility warns `unsupported node version`.

**Fix now:** Set `NODE_VERSION` in `.github/workflows/ci.yml` and `deploy-environment.yml`, `nodeVersion` in `pipelines/variables/common.yml`, and the dev container Node feature, to an LTS version the ADF utility supports (check its npm page). Merge the Dependabot Actions bumps.

**Prevent:** Review Node versions yearly (each Node LTS is supported for about 30 months).

## AGE-04 GitHub Actions runner image changes (`ubuntu-24.04` retired, or tool versions change)

**Symptom:** A job fails after GitHub updates or retires an image, or a pre-installed tool disappears.

**Fix now:** Bump `runs-on` / `vmImage` to the current LTS image. The workflows install their tools themselves (Terraform, Python, Java, Node, Databricks CLI, sqlcmd), which keeps the impact small.

**Prevent:** Watch the GitHub changelog and runner-images announcements.

## AGE-05 Terraform CLI and provider versions fall behind

**Symptom:** New provider releases need a newer Terraform, or a provider major version is announced for the end of the old line.

**Fix now:** Merge the Dependabot provider PRs, one major version at a time ([TF-11](04-terraform-and-azure.md#tf-11-provider-major-upgrade-breaks-validate-or-plan)). Bump the Terraform CLI version in all three places ([TF-13](04-terraform-and-azure.md#tf-13-terraform-version-too-old-for-a-new-provider-or-backend-feature)).

**Prevent:** A quarterly review. Keep modules on minimum-only constraints ([CI-03](02-ci-github-actions.md#ci-03-terraform-init-fails-locked-provider--does-not-match-configured-version-constraint)).

## AGE-06 Azure service retirements or API changes

**Symptom:** Azure emails about a retiring feature or SKU, portal banners, or deployments failing on a deprecated API version.

**Fix now:** Azure Advisor → Service Retirement workbook, filtered to the platform subscriptions. Plan the change in Terraform (usually a provider upgrade or a new argument).

**Prevent:** Route Service Health and retirement notifications to the team distribution list (Service Health alerts to the action group).

## AGE-07 Credentials with an expiry date

| Credential | Where | Typical lifetime | If it expires |
|---|---|---|---|
| Datadog Azure app client secret | Entra ID app + `DATADOG_AZURE_CLIENT_SECRET` | ≤ 2 years | [SEC-04](10-security-and-secrets.md#sec-04-datadog-azure-integration-secret-expires) |
| Datadog API/app keys | Datadog + GitHub/Azure DevOps secrets | until revoked (rotate yearly) | [SEC-03](10-security-and-secrets.md#sec-03-rotating-the-datadog-api-and-application-keys) |
| CRM connection string / listings API key | Key Vault | set by the source owner | [SEC-05](10-security-and-secrets.md#sec-05-crm-or-listings-credentials-rotated-by-the-source-team) |
| Synapse master key password | GitHub/Azure DevOps secrets | no expiry (rotate yearly) | [SYN-08](08-synapse-and-power-bi.md#syn-08-the-master-key-password-is-lost-or-needs-rotation) |
| Power BI data source credentials | Power BI service | OAuth tokens expire, often ~90 days | [PBI-01](08-synapse-and-power-bi.md#pbi-01-scheduled-refresh-fails-credentials-expired) |
| Personal `gh` token | Developer machine | per user settings | [CI-10](02-ci-github-actions.md#ci-10-push-rejected-refusing-to-allow-an-oauth-app-to-create-or-update-workflow) |
| Azure deployment identity | OIDC federated credential | **no secret to expire**; breaks on repo rename | [CD-02](03-cd-deployments.md#cd-02-aadsts700213-no-matching-federated-identity-record-found) |

List the Entra app secrets that expire in the next 60 days:

```bash
az ad app list --all --query "[].{app:displayName, id:appId, ends:passwordCredentials[].endDateTime}" -o json \
  | jq -r --arg cut "$(date -u -d '+60 days' +%FT%TZ)" '.[] | select(any(.ends[]?; . < $cut)) | "\(.app) \(.id) \(.ends)"'
```

## AGE-08 Delta tables accumulate history and small files

**Symptom:** Gradually slower jobs, more storage, and slower serverless queries.

**Fix now:** `OPTIMIZE` + `VACUUM` ([DBX-11](06-databricks-and-spark.md#dbx-11-job-is-getting-slower-every-week)).

**Prevent:** Schedule weekly maintenance, or enable predictive optimization.

## AGE-09 Data volume outgrows full-refresh design

See [COST-07](11-cost-and-capacity.md#cost-07-growth-jobs-tables-and-warehouse-outgrow-current-sizing).

## AGE-10 Documentation and runbooks drift from reality

**Symptom:** Runbook commands fail, or names in the docs no longer match resources.

**Fix now:** Fix the doc in the same PR that fixes the incident.

**Prevent:** The PR template checklist asks for runbook updates. Do a quarterly walkthrough of one runbook as a game day.

## AGE-11 Unused environments or resources linger

**Symptom:** Old feature workspaces, dev copies of bundles (`[dev <user>] zingy-daily-medallion-dev`), or orphaned resources still costing money.

**Fix now:**

```bash
databricks bundle destroy -t dev        # a personal dev copy
databricks jobs list | grep '\[dev '     # find others
```

**Prevent:** A monthly clean-up. Development-mode bundles are prefixed with the user's name, so they're easy to spot.

## Maintenance calendar

| Cadence | Task | Reference |
|---|---|---|
| Weekly | Merge green Dependabot PRs (Actions, pip, npm) | [CI-12](02-ci-github-actions.md#ci-12-dependabot-pr-fails-ci) |
| Weekly | Review Datadog SLOs and noisy monitors | [MON-04](09-monitoring-datadog.md#mon-04-too-many-alerts-noise) |
| Monthly | Cost review per environment. Pause or clean unused resources. | [COST-*](11-cost-and-capacity.md) |
| Monthly | Terraform drift check: `plan -refresh-only` per environment | [TF-02](04-terraform-and-azure.md#tf-02-drift-someone-changed-resources-in-the-portal) |
| Monthly | Check for credentials expiring within 60 days | [AGE-07](#age-07-credentials-with-an-expiry-date) |
| Quarterly | Databricks runtime, Python, Node, Terraform and provider versions | AGE-01 to AGE-05 |
| Quarterly | Access review (Entra groups, RBAC, GitHub environment reviewers) | [SEC-06](10-security-and-secrets.md#sec-06-someone-was-granted-too-much-access-or-a-leaver-still-has-access) |
| Quarterly | Game day: run one runbook end to end in uat | [runbooks](../runbooks/) |
| Yearly | Rotate Datadog keys and the Synapse master key. Rehearse the DR failover in uat. | [SEC-03](10-security-and-secrets.md#sec-03-rotating-the-datadog-api-and-application-keys), [disaster-recovery.md](../disaster-recovery.md) |
