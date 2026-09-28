# Data quality and data issues (`DATA-*`)

Quarantine query, used throughout this file:

```python
q = spark.read.format("delta").load("abfss://quarantine@<acct>.dfs.core.windows.net/<entity>")
q.where("_run_date = '<date>'").selectExpr("explode(_dq_failures) AS rule").groupBy("rule").count().show()
```

## DATA-01 Rejection-rate alert fires

**Symptom:** Datadog `Data quality rejection rate` above 1% for a `source`/`entity`.

**Fix now:** Follow the [data-quality-breach runbook](../runbooks/data-quality-breach.md). Decide whether it's a source defect (escalate), a legitimate new value (update the rule in `quality.py`), or a schema change ([DATA-03](#data-03-source-schema-changed-new-renamed-or-retyped-column)).

**Prevent:** Agree data contracts with the source owners.

## DATA-02 All rows for one entity rejected

**Symptom:** `rejected == processed` for one entity.

**Cause:** Almost always a schema or format change. A renamed column becomes NULL, and `try_cast` turns a new format (for example `DD/MM/YYYY` dates) into NULL, so a "present" or "positive" rule fails for every row.

**Fix now:** Compare a raw landing file with the expected schema:

```python
spark.read.parquet("abfss://landing@<acct>.dfs.core.windows.net/crm/<entity>/ingest_date=<date>").printSchema()
```

Update `entities.py` (column names and types) and the ADF mapping if needed. Deploy, then rerun the date: the rows move from quarantine to silver.

**Prevent:** Add a volume check: alert when `records_rejected / records_processed` is 1.0.

## DATA-03 Source schema changed: new, renamed, or retyped column

**Behaviour today:**
- **New column:** bronze keeps it (`mergeSchema`). Silver ignores it until it's added to `entities.py`.
- **Renamed column:** silver sees NULL for the old name, and DQ rejects the rows if a rule covers that column. Otherwise the NULLs flow through silently.
- **Type change:** `try_cast` gives NULL for values that don't convert.

**Fix now:** Add or rename the column in `entities.py`, then update `gold.py`, the Synapse `stg.*` tables (as a new `V###` migration), and the Power BI model if the column is exposed. Rerun the affected dates.

**Prevent:** A contract test that reads a sample of each landing file and asserts the expected columns exist.

## DATA-04 Zero rows arrived today

**Symptom:** Bronze counts are 0, and the freshness alert fires.

**Cause:** The source was empty or down, the ADF copy failed, or the extract ran against the wrong database.

**Fix now:** Check ADF ([ADF-06](05-data-factory.md#adf-06-pipeline-did-not-run-overnight), [ADF-03](05-data-factory.md#adf-03-crm-source-unreachable-or-login-fails)) and the landing folder for the date. Rerun once the source recovers.

**Prevent:** Add a Datadog monitor on `zingyestates.databricks.records_processed{zone:bronze}` being 0 for any entity.

## DATA-05 Sudden drop or spike in volume (for example 50% fewer properties)

**Cause:** A partial extract, source filter changes, or a duplicate extract (a spike).

**Fix now:** Compare day-over-day counts in `bronze` by `_run_date`. If the extract was partial, rerun ingestion and the job for that date. Silver `MERGE` is safe to rerun.

**Prevent:** Add an anomaly monitor in Datadog (`anomalies()` on `records_processed`).

## DATA-06 An update to a record didn't show up

**Symptom:** The source changed a property, but silver and gold still show the old value.

**Cause:** The silver merge updates only when `s.updated_at >= t.updated_at`. If the source didn't bump `updated_at`, or sends an older timestamp, the change is ignored.

**Fix now:** Confirm the source `updated_at` for that key in bronze. As a one-off, correct the row manually in silver, or temporarily loosen the condition in `silver.upsert` and rerun.

**Prevent:** Require the source to maintain `updated_at` (a data contract). Monitor for rows where bronze differs from silver with equal timestamps.

## DATA-07 Records deleted in the source still appear in reports

**Cause:** This is a design limitation. The CRM is fully extracted and merged, and the merge never deletes rows that are missing from the extract.

**Fix now:** For a known deletion, delete it from silver, and gold drops it on the next rebuild:

```sql
DELETE FROM delta.`abfss://silver@<acct>.dfs.core.windows.net/properties` WHERE property_id = 'PR01234';
```

**Prevent:** Choose one:
- Have the source send soft-delete flags (`is_deleted`) and filter them in gold.
- Add `.whenNotMatchedBySourceDelete()` to the merge. Only do this for entities that are always fully extracted, and guard against empty extracts (see DATA-04) first.

## DATA-08 Duplicates increasing (`data.quality.duplicates`)

**Cause:** The source sends several versions of the same key in one extract. That's normal for change feeds and they're deduplicated. A sudden rise suggests an extract bug.

**Fix now:** Check the duplicate keys in bronze for the date. Silver keeps the latest by `updated_at`, so output stays correct.

**Prevent:** Alert if duplicates exceed an agreed threshold.

## DATA-09 Backfilling several days

**Fix now:** Run the dates in order (oldest first):

```bash
for d in 2026-09-20 2026-09-21 2026-09-22; do
  az datafactory pipeline create-run -g rg-zingyestates-<env>-data --factory-name adf-zingy-<env>-<sfx> \
    --name pl_master_daily --parameters "{\"run_date\":\"$d\"}"
  # wait for each to finish (scripts/smoke-test-adf.sh shows a polling loop)
done
```

If landing already has the files, run just the Databricks job per date (`databricks jobs run-now ... run_date`).

**Prevent:** Keep ingestion and transforms idempotent per date. They are today.

## DATA-10 Wrong day's data processed (timezone confusion)

**Symptom:** Data for "yesterday" appears under today's `run_date`, or the reverse.

**Cause:** Every `run_date` is **UTC** (trigger at 02:00 UTC, `utcNow()`, and `spark.sql.session.timeZone=UTC`). Business users may expect local time.

**Fix now:** Rerun with an explicit `run_date`. Present local-time views in Power BI instead.

**Prevent:** Document UTC in reports. Store source timestamps as UTC.

## DATA-11 Bad data reached gold and reports

**Fix now:** Fix the rule, code or source. Restore silver if it was corrupted ([DBX-10](06-databricks-and-spark.md#dbx-10-bad-data-written-restore-a-delta-table)). Rerun the job (gold rebuilds). Reload Synapse (`pl_load_synapse`) and refresh Power BI.

**Prevent:** Tighten DQ rules for the defect you found, and add the case to `sample_data.generate` plus a test.

## DATA-12 GDPR / privacy deletion request (for example an agent's personal data)

**Fix now:** Delete from every zone, then remove the history:

```sql
DELETE FROM delta.`abfss://silver@<acct>.dfs.core.windows.net/agents` WHERE agent_id = 'AG0042';
DELETE FROM delta.`abfss://bronze@<acct>.dfs.core.windows.net/agents` WHERE agent_id = 'AG0042';
DELETE FROM delta.`abfss://quarantine@<acct>.dfs.core.windows.net/agents` WHERE agent_id = 'AG0042';
VACUUM delta.`abfss://bronze@<acct>.dfs.core.windows.net/agents` RETAIN 168 HOURS;
```

Also delete the matching landing files. Gold rebuilds on the next run. Synapse reloads and Power BI refreshes after it.

**Prevent:** Keep a record of subject-deletion requests. Consider pseudonymising personal data in silver.

## DATA-13 Referential gaps: sales for properties that don't exist

**Symptom:** `fact_sales` rows with NULL `price_per_sqft`, or Power BI shows "(Blank)" properties.

**Cause:** The property was rejected by DQ or arrived later than its sale. `fact_sales` uses a left join to properties.

**Fix now:** Look for the `property_id` in quarantine. Fix the source and rerun.

**Prevent:** Add a DQ rule or a monitor for orphan foreign keys.

## DATA-14 `dim_date` doesn't cover a new date range

**Cause:** `dim_date` spans the min to max fact dates, expanded to whole years. Future-dated leases extend it automatically, but a Power BI slicer set before the data arrived may look empty.

**Fix now:** Rerun gold. `dim_date` rebuilds from the current facts.

**Prevent:** Nothing needed. This fixes itself.
