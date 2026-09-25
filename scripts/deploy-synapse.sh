#!/usr/bin/env bash
# Deploys synapse/ SQL to one environment. Runs inside an AzureCLI@2 task (or
# after `az login` locally); sqlcmd authenticates with the same Entra identity.
#
# Required environment variables (the pipeline sets these from Terraform outputs):
#   RESOURCE_GROUP, SYNAPSE_WORKSPACE, SERVERLESS_ENDPOINT, DEDICATED_ENDPOINT,
#   STORAGE_ACCOUNT, ADF_NAME, REPORTING_GROUP_NAME, SYNAPSE_MASTER_KEY_PASSWORD
# Optional:
#   DEDICATED_POOL   - empty when the dedicated pool is disabled
set -euo pipefail

: "${RESOURCE_GROUP:?}" "${SYNAPSE_WORKSPACE:?}" "${SERVERLESS_ENDPOINT:?}" "${STORAGE_ACCOUNT:?}"
: "${ADF_NAME:?}" "${REPORTING_GROUP_NAME:?}" "${SYNAPSE_MASTER_KEY_PASSWORD:?}"
DEDICATED_POOL="${DEDICATED_POOL:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)/synapse"
AUTH=(--authentication-method ActiveDirectoryDefault)

# --- temporary firewall opening for this agent ------------------------------
AGENT_IP="$(curl -fsS https://api.ipify.org)"
RULE="ci-agent-$(date +%s)"
echo "Opening Synapse firewall for $AGENT_IP ($RULE)"
az synapse workspace firewall-rule create --name "$RULE" --workspace-name "$SYNAPSE_WORKSPACE" \
  --resource-group "$RESOURCE_GROUP" --start-ip-address "$AGENT_IP" --end-ip-address "$AGENT_IP" -o none
trap 'az synapse workspace firewall-rule delete --name "$RULE" --workspace-name "$SYNAPSE_WORKSPACE" --resource-group "$RESOURCE_GROUP" --yes -o none || true' EXIT
sleep 30 # rule propagation

run() { # server database file
  echo "  -> $3 on $1/$2"
  # $(MasterKeyPassword) is resolved from the environment rather than passed
  # with -v, so the secret never appears on the command line.
  MasterKeyPassword="$SYNAPSE_MASTER_KEY_PASSWORD" \
  sqlcmd -S "$1" -d "$2" "${AUTH[@]}" -b -I -i "$3" \
    -v StorageAccount="$STORAGE_ACCOUNT" AdfName="$ADF_NAME" ReportingGroupName="$REPORTING_GROUP_NAME"
}

query() { # server database sql
  sqlcmd -S "$1" -d "$2" "${AUTH[@]}" -b -I -h -1 -W -Q "SET NOCOUNT ON; $3"
}

# --- serverless lakehouse (always) ------------------------------------------
echo "Serverless SQL: $SERVERLESS_ENDPOINT"
run "$SERVERLESS_ENDPOINT" master "$ROOT/serverless/001_database.sql"
for f in "$ROOT"/serverless/0[0-9][0-9]_*.sql; do
  [[ "$(basename "$f")" == 001_* ]] && continue
  run "$SERVERLESS_ENDPOINT" zingy_lakehouse "$f"
done

# --- dedicated warehouse (optional) -----------------------------------------
if [[ -z "$DEDICATED_POOL" ]]; then
  echo "Dedicated pool disabled; skipping."
  exit 0
fi
: "${DEDICATED_ENDPOINT:?}"

status="$(az synapse sql pool show --name "$DEDICATED_POOL" --workspace-name "$SYNAPSE_WORKSPACE" --resource-group "$RESOURCE_GROUP" --query status -o tsv)"
if [[ "$status" == "Paused" ]]; then
  echo "Resuming paused pool $DEDICATED_POOL"
  az synapse sql pool resume --name "$DEDICATED_POOL" --workspace-name "$SYNAPSE_WORKSPACE" --resource-group "$RESOURCE_GROUP" -o none
fi

echo "Dedicated SQL: $DEDICATED_ENDPOINT/$DEDICATED_POOL"
query "$DEDICATED_ENDPOINT" "$DEDICATED_POOL" \
  "IF OBJECT_ID('dbo.schema_migrations') IS NULL CREATE TABLE dbo.schema_migrations (version NVARCHAR(200) NOT NULL, applied_at DATETIME2 NOT NULL) WITH (DISTRIBUTION = REPLICATE, HEAP);" >/dev/null

for f in "$ROOT"/dedicated/migrations/V*.sql; do
  version="$(basename "$f" .sql)"
  applied="$(query "$DEDICATED_ENDPOINT" "$DEDICATED_POOL" "SELECT COUNT(*) FROM dbo.schema_migrations WHERE version = '$version';" | tr -d '[:space:]')"
  if [[ "$applied" == "0" ]]; then
    run "$DEDICATED_ENDPOINT" "$DEDICATED_POOL" "$f"
    query "$DEDICATED_ENDPOINT" "$DEDICATED_POOL" "INSERT INTO dbo.schema_migrations VALUES ('$version', SYSUTCDATETIME());" >/dev/null
  else
    echo "  == $version already applied"
  fi
done

# Repeatable objects: procedures first, then security (grants reference procedures).
for f in "$ROOT"/dedicated/procedures/*.sql "$ROOT"/dedicated/security/*.sql; do
  run "$DEDICATED_ENDPOINT" "$DEDICATED_POOL" "$f"
done

echo "Synapse deployment complete."
