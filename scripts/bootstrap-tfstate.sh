#!/usr/bin/env bash
# One-time: create the Terraform remote-state storage used by every environment
# (terraform/environments/*/backend.hcl and datadog/environments/*.backend.hcl).
#
#   az login && az account set --subscription <management-subscription>
#   ./scripts/bootstrap-tfstate.sh [location]
set -euo pipefail

LOCATION="${1:-eastus2}"
RG="rg-zingyestates-tfstate"
ACCOUNT="stzingytfstate"

az group create --name "$RG" --location "$LOCATION" --tags company=zingyestates service=terraform-state -o none

az storage account create \
  --name "$ACCOUNT" --resource-group "$RG" --location "$LOCATION" \
  --sku Standard_ZRS --kind StorageV2 \
  --min-tls-version TLS1_2 --allow-blob-public-access false \
  --allow-shared-key-access false \
  -o none

az storage account blob-service-properties update \
  --account-name "$ACCOUNT" --resource-group "$RG" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 30 \
  -o none

# Prevent accidental deletion of the state account.
az lock create --name tfstate-no-delete --lock-type CanNotDelete --resource-group "$RG" -o none || true

for env in dev qa uat prod; do
  az storage container create --name "tfstate-$env" --account-name "$ACCOUNT" --auth-mode login -o none
done

cat <<EOF
State storage ready: $ACCOUNT (resource group $RG).
Grant each environment's pipeline identity "Storage Blob Data Contributor" on its
tfstate-<env> container, for example:

  az role assignment create --assignee <service-connection-app-id> \\
    --role "Storage Blob Data Contributor" \\
    --scope "\$(az storage account show -n $ACCOUNT -g $RG --query id -o tsv)/blobServices/default/containers/tfstate-dev"
EOF
