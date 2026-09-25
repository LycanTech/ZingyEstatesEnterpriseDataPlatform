#!/usr/bin/env bash
# Creates the GitHub environments used by .github/workflows/deploy-environment.yml
# and loads their variables and secrets from a local, git-ignored file.
#
#   cp .github/environment.example.env .github/env/uat.env   # fill in values
#   ./scripts/setup-github-environments.sh uat .github/env/uat.env
#
# For each <env> it creates:
#   <env>             the approval gate (uat/prod: required reviewer = you, main branch only)
#   <env>-automation  unprotected, used for plan and post-infrastructure jobs
# Both get the same variables/secrets. Requires: gh (authenticated), jq.
set -euo pipefail

ENV="${1:?usage: $0 <dev|qa|uat|prod> <values-file>}"
VALUES="${2:?usage: $0 <env> <values-file>}"
REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
[[ -f "$VALUES" ]] || { echo "values file not found: $VALUES" >&2; exit 1; }

VARIABLES=(AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID SYNAPSE_ADMIN_GROUP_OBJECT_ID
           REPORTING_GROUP_NAME DATADOG_AZURE_TENANT_ID DATADOG_AZURE_CLIENT_ID)
SECRETS=(DD_API_KEY DD_APP_KEY DATADOG_AZURE_CLIENT_SECRET SYNAPSE_MASTER_KEY_PASSWORD)

set -a
# shellcheck disable=SC1090
source "$VALUES"
set +a

reviewer_id="$(gh api user -q .id)"

create_env() { # name protected(true/false)
  local name=$1 protected=$2 body
  if [[ $protected == true ]]; then
    body=$(jq -n --argjson id "$reviewer_id" \
      '{reviewers: [{type: "User", id: $id}], deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}}')
  else
    body='{"deployment_branch_policy": null}'
  fi
  gh api -X PUT "repos/$REPO/environments/$name" --input - <<<"$body" >/dev/null
  if [[ $protected == true ]]; then
    gh api -X POST "repos/$REPO/environments/$name/deployment-branch-policies" -f name=main -f type=branch >/dev/null 2>&1 || true
  fi
  for v in "${VARIABLES[@]}"; do
    [[ -n "${!v:-}" ]] && gh variable set "$v" --env "$name" --repo "$REPO" --body "${!v}"
  done
  for s in "${SECRETS[@]}"; do
    [[ -n "${!s:-}" ]] && gh secret set "$s" --env "$name" --repo "$REPO" --body "${!s}"
  done
  echo "configured environment $name (protected=$protected)"
}

protected=false
[[ $ENV == uat || $ENV == prod ]] && protected=true
create_env "$ENV" "$protected"
create_env "$ENV-automation" false

cat <<EOF

Next, in Azure, add federated credentials to the app registration $AZURE_CLIENT_ID:

  for subject in "$ENV" "$ENV-automation"; do
    az ad app federated-credential create --id "$AZURE_CLIENT_ID" --parameters "{
      \"name\": \"github-\$subject\",
      \"issuer\": \"https://token.actions.githubusercontent.com\",
      \"subject\": \"repo:$REPO:environment:\$subject\",
      \"audiences\": [\"api://AzureADTokenExchange\"]
    }"
  done

When every environment is configured, turn deployments on:
  gh variable set DEPLOY_ENABLED --repo $REPO --body true
EOF
