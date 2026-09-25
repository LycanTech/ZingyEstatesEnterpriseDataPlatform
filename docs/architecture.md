# Architecture

```
 Sources                    Ingest / orchestrate        Lake (ADLS Gen2, Delta)                 Serve              Consume
 ─────────                  ────────────────────        ───────────────────────                 ─────              ───────
 CRM (Azure SQL)  ──┐                                   landing/   raw Parquet / JSON
                    ├──▶  Azure Data Factory  ──copy──▶     │
 Listings REST API ─┘     pl_master_daily                    ▼  bronze.py   (+ ingestion metadata)
                          02:00 UTC trigger             bronze/    append-only Delta per run date
                              │                              │  silver.py   (type, DQ, dedupe, MERGE)
                              │  DatabricksJob               ▼            └──▶ quarantine/  (failed rows + reasons)
                              └──────────────────────▶  silver/    conformed Delta
                                                             │  gold.py     (star schema)
                                                             ▼
                                                        gold/      dim_*, fact_*, agg_*  ──▶ Synapse serverless views ──▶ Power BI
                                                        gold/_exports  Parquet snapshots  ──▶ Synapse dedicated dw.*  ──▶ Power BI
                                                                                                  (pl_load_synapse)
 Observability: Datadog (Azure integration + zingyestates.* custom metrics) · Log Analytics (diagnostics)
 Security:      Managed identities · Key Vault · private endpoints · Unity Catalog · Entra ID groups
```

## Components

| Layer | Implementation | Code |
|---|---|---|
| Ingestion | ADF copy activities on a managed-VNet integration runtime. CRM tables are fully extracted to Parquet and the API is paged to JSON Lines. | `adf/pipeline/pl_ingest_*.json` |
| Orchestration | `pl_master_daily`: resolve run date, ingest (in parallel), run the Databricks job, then load Synapse if enabled | `adf/pipeline/pl_master_daily.json` |
| Bronze | Lands each run date as a Delta partition (`replaceWhere`), so reruns are idempotent | `databricks/src/zingyestates/bronze.py` |
| Silver | `try_cast` to the target schema, standardisation, declarative DQ rules, latest-per-key dedupe, Delta `MERGE` | `silver.py`, `quality.py`, `entities.py` |
| Gold | Star schema plus a monthly market aggregate, fully rebuilt each run, with Parquet export snapshots | `gold.py` |
| Serving | Synapse serverless `OPENROWSET(FORMAT='DELTA')` views. Optional dedicated pool loaded with COPY INTO and a CTAS + rename swap. | `synapse/` |
| Metrics | Pipeline, DQ, and freshness metrics follow `datadog/metrics-contract.md` | `metrics.py`, `datadog/` |

## Data model (gold)

- `dim_property`, `dim_agent`: surrogate key `xxhash64(<natural key>)`.
- `dim_date`: calendar spanning every fact date.
- `fact_sales`: price, price per sq ft, and days to close.
- `fact_leases`: rent, term, and annualised rent.
- `fact_listings`: current listing status and days on market.
- `agg_market_monthly`: sales count, volume, median price, and average price per sq ft by city and month.

## Design decisions

- **Medallion on Delta.** ACID MERGE, time travel for audit and recovery, and one format for Spark and Synapse serverless.
- **Idempotency by run date.** Every stage can be rerun for a date without creating duplicates (`test_rerun_is_idempotent`).
- **Quarantine, not drop.** Bad rows are kept with the names of the rules they failed, so data owners can fix them at the source.
- **One package, many runtimes.** The same wheel runs on Databricks, in Docker, and in CI. Only `PlatformConfig` changes.
- **ADF owns orchestration and Databricks owns compute.** The Databricks job has no schedule of its own, so there's a single place to see and rerun a day.
- **Asset Bundles for Databricks.** Jobs are defined as code, versioned with the transformations, and deployed per target.
- **Serverless first.** Dedicated SQL is optional and off in dev and qa to control cost.
