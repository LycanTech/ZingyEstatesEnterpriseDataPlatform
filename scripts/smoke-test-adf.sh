#!/usr/bin/env bash
# Triggers pl_master_daily and waits for it to finish. Used after QA/UAT
# deployments; safe to run by hand after `az login`.
#
#   RESOURCE_GROUP=rg-zingyestates-qa-data ADF_NAME=adf-zingy-qa-ze01 ./scripts/smoke-test-adf.sh
set -euo pipefail
: "${RESOURCE_GROUP:?}" "${ADF_NAME:?}"
TIMEOUT_MINUTES="${TIMEOUT_MINUTES:-90}"

az extension add --name datafactory --only-show-errors >/dev/null 2>&1 || true

run_id="$(az datafactory pipeline create-run --resource-group "$RESOURCE_GROUP" --factory-name "$ADF_NAME" \
  --name pl_master_daily --query runId -o tsv)"
echo "Started pl_master_daily run $run_id"

deadline=$((SECONDS + TIMEOUT_MINUTES * 60))
while (( SECONDS < deadline )); do
  status="$(az datafactory pipeline-run show --resource-group "$RESOURCE_GROUP" --factory-name "$ADF_NAME" \
    --run-id "$run_id" --query status -o tsv)"
  echo "$(date -u +%H:%M:%S) $status"
  case "$status" in
    Succeeded) exit 0 ;;
    Failed|Cancelled)
      az datafactory activity-run query-by-pipeline-run --resource-group "$RESOURCE_GROUP" --factory-name "$ADF_NAME" \
        --run-id "$run_id" --last-updated-after 2000-01-01 --last-updated-before 2100-01-01 \
        --query "value[?status=='Failed'].{activity:activityName,error:error.message}" -o table
      exit 1 ;;
  esac
  sleep 30
done
echo "Timed out after ${TIMEOUT_MINUTES} minutes" >&2
exit 1
