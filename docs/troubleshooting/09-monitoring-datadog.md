# Monitoring and Datadog (`MON-*`)

## MON-01 Dashboard shows no `zingyestates.*` metrics

**Cause:** The job clusters have no Datadog API key (the secret scope is missing), the key is invalid, the site doesn't match (EU accounts use `datadoghq.eu`), or the environment filter on the dashboard is wrong.

**Fix now:**

```bash
curl -s -H "DD-API-KEY: $DD_API_KEY" "https://api.${DD_SITE:-datadoghq.com}/api/v1/validate"   # {"valid":true}
databricks secrets list-secrets zingy-platform
```

Check the job's driver log for `metrics=api` (the key was found) or `metrics=log` (no key). For a non-US site, set `DD_SITE` in `spark_env_vars` (`databricks/resources/*.yml`) and `datadog_api_url` in the Datadog tfvars.

**Prevent:** The metrics code never fails the pipeline, so a missing key is silent. Add a Datadog "no data" monitor on `zingyestates.data.pipeline.execution` over 26 hours.

## MON-02 Azure metrics (ADF, storage) missing in Datadog

**Cause:**
- The Datadog Azure app's client secret expired.
- The app lost **Monitoring Reader**.
- `host_filters` doesn't match the Azure resource tags.

The filter must use the tag keys Terraform sets on resources: `company:<company>,environment:<env>`. An earlier version filtered on `env:`, which matches nothing.

**Fix now:** In Datadog → Integrations → Azure, check for errors on the app. Then:

```bash
az ad app credential list --id <datadog-app-client-id> --query "[].endDateTime"
az role assignment list --assignee <datadog-app-client-id> --all -o table
```

Rotate the secret ([SEC-04](10-security-and-secrets.md#sec-04-datadog-azure-integration-secret-expires)) and rerun CD.

**Prevent:** Track the secret expiry date ([AGE-07](12-aging-and-maintenance.md#age-07-credentials-with-an-expiry-date)).

## MON-03 A monitor never alerts even though failures happened

**Cause:** The query tags or metric name don't match what's emitted. The ADF monitor uses `azure.datafactory_factories.pipeline_failed_runs{company:...,environment:...}` (the original `azure.datafactory.pipeline_failed{...,env:...}` would never match).

**Fix now:** In Datadog → Metrics → Explorer, confirm the metric name and the available tags, then fix the query in `datadog/monitors.tf` and deploy.

**Prevent:** After any monitor change, test it (Datadog monitor → "Test notifications"), and confirm it fires by causing a failure in dev.

## MON-04 Too many alerts (noise)

**Symptom:** The duration or freshness monitors fire during expected long runs or backfills.

**Fix now:** Mute the monitor for the backfill window: Datadog → monitor → Mute, scoped to `env:<env>`.

**Prevent:** Tune thresholds per environment. Add `renotify_interval` and `evaluation_delay`. Send non-prod alerts to a separate handle (`datadog/environments/<env>.tfvars`).

## MON-05 Freshness SLO keeps breaching even though data is fine

**Cause:** Freshness is measured at the end of the gold step as the minutes since the newest `_ingested_at`. Runs that take longer than 30 minutes from bronze to gold breach it.

**Fix now:** Check `zingyestates.data.freshness_minutes`. If the runs are legitimately longer now, raise `FRESHNESS_THRESHOLD_MINUTES` in `gold.py` and the monitor threshold together.

**Prevent:** Review the thresholds when data volume grows.

## MON-06 Terraform for Datadog fails: `403 Forbidden` / `Invalid API key`

**Cause:** `DD_API_KEY`/`DD_APP_KEY` was revoked, rotated, or belongs to the wrong org or site. Application keys also need the scopes for monitors, dashboards, SLOs and integrations.

**Fix now:** Create new keys in Datadog → Organization settings, then update them in GitHub (`gh secret set DD_APP_KEY --env <env>` and `--env <env>-automation`) and in the Azure DevOps variable groups.

**Prevent:** Use a service account's keys, not a person's (people leave).

## MON-07 Duplicate dashboards or monitors after renaming

**Cause:** A renamed Terraform resource address makes Terraform create a new object and destroy the old one. If state was lost, the old one is left behind.

**Fix now:** Delete the orphan in Datadog, or `terraform import` it.

**Prevent:** Use `moved` blocks when renaming resources.

## MON-08 Log Analytics shows no ADF or Databricks logs

**Cause:** The diagnostic setting is missing (someone deleted it), or the category group isn't supported by that resource type.

**Fix now:** `az monitor diagnostic-settings list --resource <resource-id> -o table`, then rerun the Terraform stage (`modules/diagnostics`).

**Prevent:** Terraform owns every diagnostic setting.

## MON-09 No one got paged

**Cause:** `notification_handle` isn't set up in Datadog (Teams or PagerDuty integration), or the handle name is wrong.

**Fix now:** Test from Datadog: create a test monitor with the handle. Check Datadog → Integrations → Microsoft Teams / PagerDuty.

**Prevent:** After onboarding, trigger a real test alert in each environment.
