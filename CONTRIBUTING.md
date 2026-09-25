# Contribution Rules

1. Create a feature branch from `develop` (`feature/<short-name>`).
2. Make the smallest safe change.
3. Run the checks locally:
   - `make lint` (Ruff, terraform fmt, TFLint)
   - `make test-docker` (unit and Spark tests)
   - `make tf-validate` and `make adf-validate` if you changed `terraform/`, `datadog/`, or `adf/`
4. Open a pull request into `develop` and complete the PR template checklist.
5. Obtain the required reviewers.
6. Let CI complete before merging.
7. Production changes require the configured environment approval.

## Conventions

- **Terraform:** one concern per module, with variables and outputs in their own files. Environment differences go in `environments/<env>/terraform.tfvars`, never in `if env ==` logic.
- **Synapse dedicated SQL:** schema changes are new `V###__description.sql` files. Never edit a migration that has already been applied. Procedures and grants are repeatable and are rerun on every deploy.
- **ADF:** author in the dev factory (Git-connected) or edit the JSON directly. Values that differ by environment must be parameterised in `arm-template-parameters-definition.json` and overridden in `pipelines/templates/adf-deploy.yml`.
- **PySpark:** keep transformations pure. Every new entity needs data-quality rules and sample data, and new metrics must follow `datadog/metrics-contract.md`.
- **Secrets:** never in code, tfvars, or pipeline YAML. Use Key Vault or secret variable groups. Gitleaks runs on commit and in CI.
