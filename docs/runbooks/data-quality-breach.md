# Runbook: data-quality rejection rate above 1%

**Alert:** `ZingyEstates - Data quality rejection rate` · the tags `source` and `entity` identify the feed

Rejected rows aren't lost. They're in `quarantine/<entity>`, each with a `_dq_failures` array that names the rules it failed (`databricks/src/zingyestates/quality.py`).

1. **See which rules failed and how often:**
   ```python
   q = spark.read.format("delta").load("abfss://quarantine@<account>.dfs.core.windows.net/<entity>")
   q.where("_run_date = '<date>'").selectExpr("explode(_dq_failures) rule").groupBy("rule").count().show()
   q.where("_run_date = '<date>'").show(20, truncate=False)
   ```
2. **Decide:**
   - **Source defect** (for example, prices of 0 or bad emails): raise it with the source data owner, with sample IDs. Silver and gold already exclude those rows, so reports stay correct.
   - **Legitimate new value** (for example, a new `property_type`): update the rule in `quality.py`, add a test, and deploy. Then rerun the day so the rows move from quarantine to silver.
   - **Schema change** (a whole column is NULL after `try_cast`): update `entities.py`, add a test, deploy, and rerun.
3. Record the incident and the decision in the team channel. Frequent rejections from the same rule mean the data contract with the source needs to be revisited.
