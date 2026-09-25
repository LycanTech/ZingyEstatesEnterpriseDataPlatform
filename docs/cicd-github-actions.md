# CI/CD with GitHub Actions

GitHub Actions runs the same flow as the Azure DevOps pipeline (`azure-pipelines.yml`). The two are independent, so you can use either or both.

## Workflows

| File | Trigger | What it does |
|---|---|---|
| `.github/workflows/ci.yml` | Push to `main`, `develop`, or `feature/**`; PRs; manual | Terraform fmt/validate/TFLint (Azure and Datadog), Checkov, Gitleaks, Ruff, pytest (unit and Spark, Java 17), wheel build, ADF validate and ARM export. **Needs no secrets.** |
| `.github/workflows/cd.yml` | CI succeeded on a push to `develop`/`main`; or manual, with an environment input | `develop` deploys dev. `main` deploys qa, then uat (approval), then prod (approval). Does nothing unless `vars.DEPLOY_ENABLED == 'true'`. |
| `.github/workflows/deploy-environment.yml` | Called by `cd.yml` | Plan, then an approval-gated infrastructure apply, then the Databricks bundle, Data Factory, Synapse, and an optional smoke test |
| `.github/actions/terraform-outputs` | Composite action | Exports Terraform outputs as environment variables for the deploy steps |
| `.github/dependabot.yml` | Weekly/monthly | Updates actions, pip (PySpark and Delta are pinned to the Databricks runtime), npm, and Terraform providers |

## How a deployment flows

```
push main ─▶ CI ✔ ─▶ CD
                     ├─ qa   : plan ─▶ infrastructure ─▶ databricks ─▶ data-factory ─▶ smoke-test
                     │                                └▶ synapse ────────────────────┘
                     ├─ uat  : plan ─▶ [approval] ─▶ infrastructure ─▶ ... ─▶ smoke-test
                     └─ prod : plan ─▶ [approval] ─▶ infrastructure ─▶ ...
```

The Terraform plans are written to the **Plan job summary**. Reviewers read them there before approving the `infrastructure` job. Plan files are not uploaded as artifacts: **this repository is public**, and plan files can contain sensitive values. After approval, the apply job re-plans from the same commit and applies.

## One-time setup

### 1. Azure: an app registration per environment (OIDC, no secret)

```bash
az ad app create --display-name gh-zingyestates-dev
az ad sp create --id <appId>
az role assignment create --assignee <appId> --role Owner --scope /subscriptions/<dev-subscription-id>
# plus Storage Blob Data Contributor on the tfstate-dev container (see scripts/bootstrap-tfstate.sh)
```

**Owner** (or Contributor + User Access Administrator) is needed because Terraform creates role assignments.

### 2. GitHub: environments, variables, and secrets

Each environment uses two GitHub environments:

- `<env>`: the approval gate, used only by the infrastructure job. uat and prod get a required reviewer and a `main`-only branch policy.
- `<env>-automation`: unprotected, used for the plan and post-infrastructure jobs so you approve once per environment.

The script creates both and loads the same values into each:

```bash
mkdir -p .github/env                                   # git-ignored
cp .github/environment.example.env .github/env/dev.env # fill in
./scripts/setup-github-environments.sh dev .github/env/dev.env
```

| Name | Type | Purpose |
|---|---|---|
| `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | variable | OIDC login and the Terraform `ARM_*` variables |
| `SYNAPSE_ADMIN_GROUP_OBJECT_ID` | variable | Synapse Entra ID admin |
| `REPORTING_GROUP_NAME` | variable | Power BI readers in Synapse |
| `DATADOG_AZURE_TENANT_ID`, `DATADOG_AZURE_CLIENT_ID` | variable | Datadog Azure integration |
| `DATADOG_AZURE_CLIENT_SECRET` | secret | Datadog Azure integration |
| `DD_API_KEY`, `DD_APP_KEY` | secret | Datadog provider and job-cluster metrics |
| `SYNAPSE_MASTER_KEY_PASSWORD` | secret | Serverless database master key |

### 3. Azure: federated credentials

The script prints the exact commands. Each app registration trusts both of its GitHub environments:

```
issuer:  https://token.actions.githubusercontent.com
subject: repo:LycanTech/ZingyEstatesEnterpriseDataPlatform:environment:dev
subject: repo:LycanTech/ZingyEstatesEnterpriseDataPlatform:environment:dev-automation
```

### 4. Turn on deployments

```bash
gh variable set DEPLOY_ENABLED --body true
```

To deploy a single environment by hand, go to **Actions → CD → Run workflow → environment**. Prod can only be dispatched from `main`.

## Recommended repository settings

- **Branch protection** on `main` and `develop`: require PRs and the CI checks `Terraform (terraform)`, `Terraform (datadog)`, `Security scans`, `PySpark lint, tests, wheel`, and `Data Factory validate + export`.
- **Actions → General:** allow only the actions this repo uses (actions/*, hashicorp/*, azure/*, terraform-linters/*).
- Because the repository is public, never paste plan output, secrets, or real data into issues or PRs.
