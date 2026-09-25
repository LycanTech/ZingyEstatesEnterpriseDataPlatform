## What changed and why

## Affected components
- [ ] Terraform (`terraform/`)
- [ ] Datadog (`datadog/`)
- [ ] Data Factory (`adf/`)
- [ ] Databricks jobs / PySpark (`databricks/`)
- [ ] Synapse SQL (`synapse/`)
- [ ] CI/CD (`azure-pipelines.yml`, `pipelines/`)

## Checks
- [ ] `make lint` and `make test-docker` pass locally
- [ ] Terraform plan reviewed (readable plan artifact attached by CI)
- [ ] New Synapse schema changes are a new `V###__*.sql` migration, not an edit to an applied one
- [ ] Data-quality rules / metrics contract updated if data shape changed
- [ ] Runbooks updated if alerting or operational behaviour changed
