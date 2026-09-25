-- Run against: zingy_lakehouse (serverless). Repeatable.
-- Views read the gold Delta tables written by databricks/src/zingyestates/gold.py.

CREATE OR ALTER VIEW gold.dim_property AS
SELECT * FROM OPENROWSET(BULK 'dim_property/', DATA_SOURCE = 'gold_lake', FORMAT = 'DELTA') AS r;
GO

CREATE OR ALTER VIEW gold.dim_agent AS
SELECT * FROM OPENROWSET(BULK 'dim_agent/', DATA_SOURCE = 'gold_lake', FORMAT = 'DELTA') AS r;
GO

CREATE OR ALTER VIEW gold.dim_date AS
SELECT * FROM OPENROWSET(BULK 'dim_date/', DATA_SOURCE = 'gold_lake', FORMAT = 'DELTA') AS r;
GO

CREATE OR ALTER VIEW gold.fact_sales AS
SELECT * FROM OPENROWSET(BULK 'fact_sales/', DATA_SOURCE = 'gold_lake', FORMAT = 'DELTA') AS r;
GO

CREATE OR ALTER VIEW gold.fact_leases AS
SELECT * FROM OPENROWSET(BULK 'fact_leases/', DATA_SOURCE = 'gold_lake', FORMAT = 'DELTA') AS r;
GO

CREATE OR ALTER VIEW gold.fact_listings AS
SELECT * FROM OPENROWSET(BULK 'fact_listings/', DATA_SOURCE = 'gold_lake', FORMAT = 'DELTA') AS r;
GO

CREATE OR ALTER VIEW gold.agg_market_monthly AS
SELECT * FROM OPENROWSET(BULK 'agg_market_monthly/', DATA_SOURCE = 'gold_lake', FORMAT = 'DELTA') AS r;
GO
