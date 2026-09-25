# Tooling

Every tool the platform uses, where it runs, and how you get it. The fastest path is the **dev container** (`.devcontainer/`), which installs all of them. `scripts/check-prereqs.sh` reports what is missing on any machine.

## Local workstation

| Tool | Version | Used for | Install |
|---|---|---|---|
| Git | ≥ 2.40 | Source control | OS package |
| Docker Desktop | ≥ 24 | Local Spark runtime (`docker-compose.yml`), dev container | docker.com |
| VS Code + Dev Containers | latest | One-click full toolchain | code.visualstudio.com |
| Terraform | 1.9.x (≥ 1.6) | Azure + Datadog infrastructure | dev container feature / hashicorp.com |
| TFLint + azurerm ruleset | 0.53 / 0.27 | Terraform linting (`.tflint.hcl`) | dev container feature |
| Checkov | 3.2 | IaC security scanning (`.checkov.yml`) | `pip install checkov` |
| Azure CLI | ≥ 2.60 | Auth, bootstrap, smoke tests | dev container feature |
| Python | 3.11 | PySpark package, tests | dev container image |
| Java (OpenJDK) | 17 | Local Spark | dev container feature / Docker image |
| PySpark / delta-spark | 3.5.3 / 3.2.1 | Local Spark + Delta, same as DBR 15.4 LTS | `requirements-dev.txt` |
| Ruff | 0.7 | Python lint + format | `requirements-dev.txt` |
| pytest | 8.3 | Unit + Spark tests | `requirements-dev.txt` |
| pre-commit | 4.0 | Git hooks (`.pre-commit-config.yaml`) | `requirements-dev.txt` |
| Databricks CLI | ≥ 0.230 | Asset Bundles, Unity Catalog setup | `post-create.sh` |
| Node.js | 20 LTS | ADF validate/export (`adf/package.json`) | dev container feature |
| go-sqlcmd | 1.8 | Synapse SQL deployment | `post-create.sh` |
| PowerShell | 7.4 | ADF pre/post deployment script | dev container feature |
| JupyterLab | 4.2 | Exploring the local lake (`notebooks/`) | Docker image |
| Gitleaks | 8.21 | Secret scanning | pre-commit / CI |

## Azure services (provisioned by `terraform/`)

| Service | Resource name pattern | Role |
|---|---|---|
| Resource group | `rg-zingyestates-<env>-data` | Per-environment container |
| Virtual network + private DNS | `vnet-zingy-<env>` | Private endpoints and Databricks VNet injection |
| ADLS Gen2 | `stzingy<env><suffix>dl` | Medallion lake (landing, bronze, silver, gold, quarantine, catalog, synapse) |
| Key Vault | `kv-zingy-<env>-<suffix>` | Source-system credentials |
| Data Factory | `adf-zingy-<env>-<suffix>` | Ingestion and orchestration (managed VNet IR) |
| Azure Databricks (Premium) | `dbw-zingy-<env>` | Spark transformations, Unity Catalog |
| Databricks access connector | `dbac-dbw-zingy-<env>` | Managed identity for Unity Catalog storage access |
| Synapse Analytics | `syn-zingy-<env>-<suffix>` | Serverless lakehouse views and optional dedicated pool `dw_zingy` |
| Log Analytics | `log-zingy-<env>` | Diagnostic logs from every resource |
| Monitor action group | `ag-zingy-<env>-platform` | Azure-native alert routing |
| Terraform state | `stzingytfstate` / `tfstate-<env>` | Remote state (`scripts/bootstrap-tfstate.sh`) |

## SaaS and delivery

| Tool | Role | Config |
|---|---|---|
| GitHub + GitHub Actions | Source, CI/CD, environments and approvals, Dependabot | `.github/` ([guide](cicd-github-actions.md)) |
| actionlint | Workflow linting | `docker run rhysd/actionlint` |
| Azure DevOps Repos | Source, PR policy (alternative) | `.azuredevops/pull_request_template.md` |
| Azure DevOps Pipelines | CI/CD | `azure-pipelines.yml`, `pipelines/` |
| Azure DevOps Environments | Approvals and deployment history | `zingyestates-<env>` |
| Datadog | Monitors, SLOs, dashboards, Azure integration | `datadog/` |
| Power BI | Reporting | `powerbi/` |

## Pipeline agents

Microsoft-hosted `ubuntu-24.04`. The pipeline installs pinned versions of Terraform, Python, Node, the Databricks CLI, and go-sqlcmd at run time (`pipelines/variables/common.yml`), so the agent image doesn't need anything pre-installed.
