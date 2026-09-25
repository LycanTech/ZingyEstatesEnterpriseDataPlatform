#!/usr/bin/env bash
# Sourced inside AzureCLI@2 tasks (addSpnToEnvironment: true). Exposes the
# service connection's workload-identity federation token to Terraform's azurerm
# provider and backend, falling back to a client secret for secret-based
# service connections.
# servicePrincipalId, tenantId, servicePrincipalKey and idToken are injected by the task.
# shellcheck disable=SC2154
export ARM_CLIENT_ID="${servicePrincipalId:?run inside AzureCLI@2 with addSpnToEnvironment: true}"
export ARM_TENANT_ID="${tenantId}"
ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
export ARM_SUBSCRIPTION_ID
if [[ -n "${idToken:-}" ]]; then
  export ARM_USE_OIDC=true
  export ARM_OIDC_TOKEN="${idToken}"
else
  export ARM_CLIENT_SECRET="${servicePrincipalKey}"
fi
export ARM_USE_AZUREAD=true
export TF_IN_AUTOMATION=1
export TF_INPUT=0
