# Developer shortcuts. Works in the dev container, Linux, macOS and WSL.
# On Windows without make, run the commands shown by `make help` directly.

ENV ?= dev
TF  := terraform -chdir=terraform
DD  := terraform -chdir=datadog
ADF_FACTORY_ID := /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-zingyestates-dev-data/providers/Microsoft.DataFactory/factories/adf-zingy-dev-ze01

.DEFAULT_GOAL := help
.PHONY: help prereqs install lint fmt test test-docker demo notebooks tf-validate tf-plan dd-plan \
        adf-validate adf-export bundle-validate bundle-deploy synapse-deploy clean

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-16s %s\n", $$1, $$2}'

prereqs: ## Check installed tool versions
	bash scripts/check-prereqs.sh

install: ## Install Python dev dependencies and ADF build tools
	pip install -r requirements-dev.txt
	cd adf && npm ci --no-audit --no-fund

lint: ## Ruff + terraform fmt check + tflint
	ruff check .
	ruff format --check databricks tests
	$(TF) fmt -check -recursive
	$(DD) fmt -check -recursive
	tflint --chdir=terraform --recursive --config=$(CURDIR)/.tflint.hcl

fmt: ## Auto-format Python and Terraform
	ruff check --fix .
	ruff format databricks tests
	$(TF) fmt -recursive
	$(DD) fmt -recursive

test: ## Unit + Spark tests (needs Java 17 locally)
	pytest

test-docker: ## Run the full test suite in the local Spark container
	docker compose run --rm platform pytest

demo: ## Run the end-to-end medallion demo on a local lake (Docker)
	docker compose run --rm platform

notebooks: ## JupyterLab on http://localhost:8888 against the local lake
	docker compose --profile notebooks up jupyter

tf-validate: ## Validate Azure and Datadog Terraform without a backend
	$(TF) init -backend=false -input=false && $(TF) validate
	$(DD) init -backend=false -input=false && $(DD) validate

tf-plan: ## Plan Azure infrastructure: make tf-plan ENV=qa (needs az login)
	$(TF) init -reconfigure -backend-config=environments/$(ENV)/backend.hcl
	$(TF) plan -var-file=environments/$(ENV)/terraform.tfvars

dd-plan: ## Plan Datadog monitors: make dd-plan ENV=qa (needs DD_API_KEY/DD_APP_KEY)
	$(DD) init -reconfigure -backend-config=environments/$(ENV).backend.hcl
	$(DD) plan -var-file=environments/$(ENV).tfvars

adf-validate: ## Validate Data Factory resources offline
	cd adf && npm run build -- validate "$(CURDIR)/adf" "$(ADF_FACTORY_ID)"

adf-export: ## Export the ADF ARM template to adf/ArmTemplate
	cd adf && npm run build -- export "$(CURDIR)/adf" "$(ADF_FACTORY_ID)" ArmTemplate

bundle-validate: ## Validate the Databricks bundle (needs DATABRICKS_HOST)
	cd databricks && databricks bundle validate -t $(ENV)

bundle-deploy: ## Deploy the Databricks bundle: make bundle-deploy ENV=dev STORAGE=<account>
	cd databricks && databricks bundle deploy -t $(ENV) --var storage_account=$(STORAGE)

synapse-deploy: ## Deploy Synapse SQL (set the variables listed in scripts/deploy-synapse.sh)
	bash scripts/deploy-synapse.sh

clean: ## Remove local lake, build output and caches
	rm -rf .local-lake databricks/dist databricks/build adf/ArmTemplate .pytest_cache .ruff_cache
