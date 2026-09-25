#!/usr/bin/env bash
# Idempotently registers the lake with Unity Catalog so the medallion job can read
# and write abfss:// paths:
#   storage credential  zingy-<env>-lake        (the Databricks access connector)
#   external locations  zingy-<env>-<zone>      (one per ADLS file system)
# and grants the calling identity (the deployment service principal, which the
# bundle's jobs run as) READ/WRITE FILES on each location.
#
# Requires: DATABRICKS_HOST + auth (azure-cli in CI), a Unity Catalog metastore
# assigned to the workspace (automatic for new workspaces in most regions).
#
#   ./scripts/setup-unity-catalog.sh <env> <storage-account> <access-connector-id>
set -euo pipefail

ENV="${1:?env}" ACCOUNT="${2:?storage account}" CONNECTOR_ID="${3:?access connector id}"
CREDENTIAL="zingy-${ENV}-lake"
PRINCIPAL="$(databricks current-user me -o json | jq -r '.userName')"

if ! databricks storage-credentials get "$CREDENTIAL" >/dev/null 2>&1; then
  echo "Creating storage credential $CREDENTIAL"
  databricks storage-credentials create --json "{\"name\": \"$CREDENTIAL\", \"azure_managed_identity\": {\"access_connector_id\": \"$CONNECTOR_ID\"}}" >/dev/null
fi

for zone in landing bronze silver gold quarantine; do
  location="zingy-${ENV}-${zone}"
  if ! databricks external-locations get "$location" >/dev/null 2>&1; then
    echo "Creating external location $location"
    databricks external-locations create "$location" "abfss://${zone}@${ACCOUNT}.dfs.core.windows.net/" "$CREDENTIAL" >/dev/null
  fi
  databricks grants update external_location "$location" \
    --json "{\"changes\": [{\"principal\": \"$PRINCIPAL\", \"add\": [\"READ_FILES\", \"WRITE_FILES\"]}]}" >/dev/null
done

echo "Unity Catalog locations ready for $ENV (granted to $PRINCIPAL)."
