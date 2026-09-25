# ZingyEstates Enterprise Data Engineering Platform

[![CI](https://github.com/LycanTech/ZingyEstatesEnterpriseDataPlatform/actions/workflows/ci.yml/badge.svg)](https://github.com/LycanTech/ZingyEstatesEnterpriseDataPlatform/actions/workflows/ci.yml)
[![CD](https://github.com/LycanTech/ZingyEstatesEnterpriseDataPlatform/actions/workflows/cd.yml/badge.svg)](https://github.com/LycanTech/ZingyEstatesEnterpriseDataPlatform/actions/workflows/cd.yml)

Production-oriented Azure data platform for ZingyEstates, a real-estate company. It ingests CRM and listings data, refines it through a Delta medallion lake, and serves a star schema to Power BI. Infrastructure, pipelines, jobs, SQL, monitoring, and CI/CD are all defined in this repository.

## Architecture

```
CRM (Azure SQL) ─┐                          ┌─ landing ─▶ bronze ─▶ silver ─▶ gold ─┬─▶ Synapse serverless ─┐
                 ├─▶ Azure Data Factory ───▶│  (ADLS Gen2 + Delta, Databricks jobs)  │                        ├─▶ Power BI
Listings API ────┘   daily orchestration    └─ quarantine (failed DQ rules)          └─▶ Synapse dedicated ───┘

Terraform (Azure + Datadog) · GitHub Actions / Azure DevOps CI/CD dev → qa → uat → prod · Datadog monitors/SLOs · Key Vault · managed identities · private endpoints
```

Details: [docs/architecture.md](docs/architecture.md)

## Try it locally in 2 commands

You only need Docker. No Azure account is required.

```bash
docker compose build platform
docker compose run --rm platform            # generates source data, runs bronze -> silver -> gold, prints results
docker compose run --rm platform pytest     # 21 unit + Spark tests
```

More options (dev container, notebooks, local Datadog agent): [docs/local-development.md](docs/local-development.md)

## Repository

| Path | What it is |
|---|---|
| [`terraform/`](terraform/) | Azure infrastructure: root module, `modules/` (networking, storage, key_vault, data_factory, databricks, synapse, monitoring, diagnostics, private_endpoint), and `environments/<env>/` |
| [`datadog/`](datadog/) | Datadog Azure integration, monitors, SLOs, dashboard, metrics contract |
| [`adf/`](adf/) | Data Factory (Git format): linked services, datasets, pipelines, trigger, managed-VNet IR, ARM export config |
| [`databricks/`](databricks/) | PySpark package `zingyestates` (bronze/silver/gold, DQ, metrics) and the Asset Bundle `databricks.yml` |
| [`synapse/`](synapse/) | Serverless lakehouse views, dedicated-pool migrations, load procedure, security |
| [`powerbi/`](powerbi/) | Semantic model, measures, RLS, refresh guidance |
| [`.github/`](.github/) | **GitHub Actions**: `ci.yml` (validate, test, scan, build), `cd.yml` → reusable `deploy-environment.yml`, composite actions, Dependabot |
| [`azure-pipelines.yml`](azure-pipelines.yml), [`pipelines/`](pipelines/) | **Azure DevOps** equivalent: stage template per environment, step templates, variables |
| [`scripts/`](scripts/) | State bootstrap, Unity Catalog setup, Synapse deploy, ADF smoke test, prerequisite check |
| [`tests/`](tests/) | `unit/` (no Spark) and `spark/` (local Spark + Delta, end-to-end) |
| [`docker/`](docker/), [`docker-compose.yml`](docker-compose.yml) | Local Spark 3.5 / Delta 3.2 runtime matching Databricks 15.4 LTS |
| [`.devcontainer/`](.devcontainer/) | VS Code dev container with every tool pre-installed |
| [`notebooks/`](notebooks/) | Exploration notebook for the local lake |
| [`docs/`](docs/) | Architecture, tooling, environments, security, operations, DR, runbooks |

## CI/CD

There are two equivalent implementations. Use either one, or both.

| | GitHub Actions | Azure DevOps |
|---|---|---|
| CI on every push and PR | `.github/workflows/ci.yml` | `CI` stage in `azure-pipelines.yml` |
| Deploy dev → qa → uat → prod | `cd.yml` + `deploy-environment.yml` | `pipelines/stages/deploy-environment.yml` |
| Azure auth | OIDC federated credential (no secrets) | Workload identity service connection |
| Approvals | GitHub environments `uat`, `prod` | Azure DevOps environments |
| Setup guide | [docs/cicd-github-actions.md](docs/cicd-github-actions.md) | [docs/environments.md](docs/environments.md) |

CI needs no credentials and runs on every push and pull request. It runs these checks:

- **Terraform** (Azure and Datadog): `fmt`, `validate`, TFLint
- **Security**: Checkov IaC scan (exceptions justified in `.checkov.yml`) and a Gitleaks secret scan
- **Python**: Ruff lint and format, pytest (unit and Spark tests on Java 17), wheel build
- **Data Factory**: validate every resource and export the ARM template

CD stays off until the `DEPLOY_ENABLED` repository variable is set to `true`.

## Secrets and sensitive values

The repository contains no credentials, tenant or subscription IDs, or connection strings. Committed files hold only non-secret configuration and all-zero placeholder IDs. Sensitive values live in:

| Value | Stored in | Reaches the code via |
|---|---|---|
| Azure identity for deployments | OIDC federated credential / workload identity service connection | Short-lived tokens. No client secret. |
| Tenant IDs, subscription IDs, group object IDs | GitHub environment variables / Azure DevOps variable groups | `ARM_*` and `TF_VAR_*` environment variables |
| Datadog keys, Datadog Azure app secret, Synapse master key password | GitHub environment secrets / secret variable groups | Environment variables. The Terraform variables are marked `sensitive`, so plans redact them. |
| Source-system credentials (CRM, listings API) | Azure Key Vault | Data Factory Key Vault linked service |
| Datadog key for Databricks job clusters | Databricks secret scope `zingy-platform` | `{{secrets/...}}` reference in the job cluster config |

Secrets are never passed as command-line arguments (they are piped via stdin or set as environment variables). Plan files are not uploaded as artifacts, because this repository is public. Local values go in git-ignored files (`.env`, `.github/env/*.env`); templates are in `.env.example` and `.github/environment.example.env`. Gitleaks runs in pre-commit and CI. See [docs/security.md](docs/security.md).

## Dependency updates

Dependabot (`.github/dependabot.yml`) opens pull requests for GitHub Actions, pip, npm (ADF utilities), and the Terraform providers. CI must pass before you merge. Two things to know:

- `pyspark` and `delta-spark` are pinned to match Databricks Runtime 15.4 LTS and are excluded from Dependabot. Upgrade them together with `spark_version` in `databricks/resources/*.yml`.
- Terraform modules declare only a minimum `azurerm` version. The root `terraform/versions.tf` sets the allowed range (currently `~> 5.6`), so a provider upgrade is a one-line change in that file plus any schema fixes `terraform validate` reports.

## Environments

`local → dev → qa → uat → prod`. The `develop` branch deploys dev. `main` deploys qa, then uat (approval), then prod (approval). Each environment has its own subscription service connection, variable group, Terraform state, and tfvars. See [docs/environments.md](docs/environments.md).

## Tooling

Terraform, TFLint, Checkov, Azure CLI, Python 3.11, PySpark, Delta, Java 17, Ruff, pytest, pre-commit, Databricks CLI, Node 20 (ADF utilities), go-sqlcmd, PowerShell, Docker, and Gitleaks. [docs/tooling.md](docs/tooling.md) lists versions, what each tool is for, and how to install it. `bash scripts/check-prereqs.sh` checks your machine.

## Deploy to Azure

1. Create the state storage: `scripts/bootstrap-tfstate.sh`.
2. Create the service connections, environments, and variable groups ([docs/environments.md](docs/environments.md#azure-devops-setup-one-time-per-environment)).
3. Set `name_suffix` and review `terraform/environments/<env>/terraform.tfvars`.
4. Choose a CI/CD system. For GitHub Actions, run `scripts/setup-github-environments.sh` for each environment, then set `DEPLOY_ENABLED=true` ([guide](docs/cicd-github-actions.md)). For Azure DevOps, point a pipeline at `azure-pipelines.yml`. Then push to `develop`.
5. Do the first-deployment steps: approve the private endpoints and load secrets ([docs/operations.md](docs/operations.md#first-deployment)).

## Important

This repository is a strong production starter. It does not claim that every organisation-specific Azure policy, SKU, network range, identity assignment, and data source has been finalised. Review security, naming, cost, retention, compliance, and disaster-recovery requirements ([docs/security.md](docs/security.md), [docs/disaster-recovery.md](docs/disaster-recovery.md)) before production deployment.
