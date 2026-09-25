-- Dedicated SQL pool dw_zingy. Versioned migration: runs once (tracked in dbo.schema_migrations).

CREATE SCHEMA stg;
GO
CREATE SCHEMA dw;
GO

-- Tables loaded by dw.usp_load_all, in order, with their distribution.
CREATE TABLE dw.load_config
(
    table_name   NVARCHAR(128) NOT NULL,
    distribution NVARCHAR(200) NOT NULL,
    load_order   INT           NOT NULL,
    enabled      BIT           NOT NULL
)
WITH (DISTRIBUTION = REPLICATE, HEAP);
GO

CREATE TABLE dw.load_audit
(
    run_date    DATE          NOT NULL,
    table_name  NVARCHAR(128) NOT NULL,
    row_count   BIGINT        NULL,
    started_at  DATETIME2     NOT NULL,
    finished_at DATETIME2     NOT NULL
)
WITH (DISTRIBUTION = ROUND_ROBIN, HEAP);
GO

INSERT INTO dw.load_config VALUES ('dim_date',           'DISTRIBUTION = REPLICATE',              10, 1);
INSERT INTO dw.load_config VALUES ('dim_property',       'DISTRIBUTION = REPLICATE',              20, 1);
INSERT INTO dw.load_config VALUES ('dim_agent',          'DISTRIBUTION = REPLICATE',              30, 1);
INSERT INTO dw.load_config VALUES ('fact_sales',         'DISTRIBUTION = HASH(property_id)',      40, 1);
INSERT INTO dw.load_config VALUES ('fact_leases',        'DISTRIBUTION = HASH(property_id)',      50, 1);
INSERT INTO dw.load_config VALUES ('fact_listings',      'DISTRIBUTION = HASH(property_id)',      60, 1);
INSERT INTO dw.load_config VALUES ('agg_market_monthly', 'DISTRIBUTION = REPLICATE',              70, 1);
GO
