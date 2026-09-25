# ZingyEstates Datadog

Central observability for Azure Data Factory, ADLS, Databricks, Synapse, and the custom data-quality metrics.

| File | Contents |
|---|---|
| `azure-integration.tf` | Datadog ↔ Azure integration (metrics and resource collection) |
| `monitors.tf` | ADF failure, DQ rejection rate, freshness, Databricks failure, duration. Each links to its runbook. |
| `slo.tf` | Pipeline success (99.5%) and freshness (99.0%) SLOs over 30 days |
| `dashboards.tf` | Data platform dashboard for each environment |
| `metrics-contract.md` | Metric names and required tags, emitted by `databricks/src/zingyestates/metrics.py` |
| `environments/<env>.tfvars` / `<env>.backend.hcl` | Per-environment alert routing and remote state |

## Credentials

Never commit `DD_API_KEY`, `DD_APP_KEY`, or the Azure app secret. The provider reads the Datadog keys from environment variables. The Azure integration's `azure_tenant_id`, `azure_client_id`, and `azure_client_secret` come from `TF_VAR_*` values that the pipeline maps from the variable group `vg-zingyestates-<env>`.

## Deploy

CI plans and applies this directory in every environment stage (`pipelines/stages/deploy-environment.yml`). To run it by hand:

1. Create an Entra ID app registration for Datadog and grant it **Monitoring Reader** on the subscription.
2. Export `DD_API_KEY`, `DD_APP_KEY`, and `TF_VAR_azure_tenant_id` / `TF_VAR_azure_client_id` / `TF_VAR_azure_client_secret`.
3. Run `az login`, then:
   ```bash
   terraform init -backend-config=environments/dev.backend.hcl
   terraform plan -var-file=environments/dev.tfvars
   ```
4. Check the dashboard and monitors in Datadog. Running `docker compose run --rm platform` locally with the observability profile sends test metrics tagged `env:local`.
