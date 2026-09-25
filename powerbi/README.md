# Power BI

Power BI is the reporting layer. It reads the gold star schema through Synapse and never reads the lake directly.

## Connection options

| Source | Endpoint (Terraform output) | Database | Best for |
|---|---|---|---|
| Synapse serverless | `synapse_serverless_endpoint` | `zingy_lakehouse`, schema `gold` | dev/qa, low cost, views over Delta |
| Synapse dedicated | `synapse_dedicated_endpoint` | `dw_zingy`, schema `dw` | uat/prod, high concurrency, Import or DirectQuery |

Authenticate with **Microsoft Entra ID (OAuth)**. Access comes from membership in the reporting group. The deploy script adds that group to the `reporting_reader` role (`synapse/serverless/004_security.sql`, `synapse/dedicated/security/roles.sql`).

## Semantic model

| Table | Type | Relationship |
|---|---|---|
| `fact_sales` | Fact | `property_id` → `dim_property`, `agent_id` → `dim_agent`, `sale_date_key` → `dim_date[date_key]` |
| `fact_leases` | Fact | `property_id`, `agent_id`, `lease_start_date_key` → `dim_date` |
| `fact_listings` | Fact | `property_id`, `agent_id`, `listed_date_key` → `dim_date` |
| `agg_market_monthly` | Aggregate | stand-alone, for market trend pages |
| `dim_property`, `dim_agent`, `dim_date` | Dimensions | Mark `dim_date` as the date table |

Suggested measures:

```DAX
Sales Volume        = SUM ( fact_sales[sale_price] )
Median Sale Price   = MEDIAN ( fact_sales[sale_price] )
Avg Price per SqFt  = AVERAGE ( fact_sales[price_per_sqft] )
Avg Days to Close   = AVERAGE ( fact_sales[days_to_close] )
Active Listings     = CALCULATE ( COUNTROWS ( fact_listings ), fact_listings[status] = "ACTIVE" )
Annualized Rent Roll = SUM ( fact_leases[annualized_rent] )
```

## Row-level security

Add a `Office` role filtered on `dim_agent[office]` for office managers. Map the roles to Entra ID groups in the Power BI service.

## Refresh

Schedule the dataset refresh for **03:30 UTC**. That is after the 02:00 UTC ADF trigger, with margin for the Databricks and Synapse steps. Datadog alerts on freshness if the upstream run is late (`datadog/monitors.tf`).

Store `.pbix` or PBIP project files in this folder. `.gitattributes` marks `.pbix` as binary.
