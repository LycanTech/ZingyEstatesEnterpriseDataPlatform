-- Staging tables receive gold export snapshots via COPY INTO.
-- Column order must match the select order in databricks/src/zingyestates/gold.py.

CREATE TABLE stg.dim_property
(
    property_sk   BIGINT,
    property_id   NVARCHAR(20),
    address_line  NVARCHAR(200),
    city          NVARCHAR(100),
    state         NCHAR(2),
    postal_code   NVARCHAR(10),
    property_type NVARCHAR(30),
    bedrooms      INT,
    bathrooms     FLOAT,
    square_feet   INT,
    year_built    INT,
    updated_at    DATETIME2
)
WITH (DISTRIBUTION = ROUND_ROBIN, HEAP);
GO

CREATE TABLE stg.dim_agent
(
    agent_sk       BIGINT,
    agent_id       NVARCHAR(20),
    full_name      NVARCHAR(200),
    email          NVARCHAR(320),
    office         NVARCHAR(100),
    license_number NVARCHAR(50),
    hired_date     DATE,
    updated_at     DATETIME2
)
WITH (DISTRIBUTION = ROUND_ROBIN, HEAP);
GO

CREATE TABLE stg.dim_date
(
    date_key    INT,
    [date]      DATE,
    [year]      INT,
    [quarter]   INT,
    [month]     INT,
    month_name  NVARCHAR(20),
    day_of_week INT,
    is_weekend  BIT
)
WITH (DISTRIBUTION = ROUND_ROBIN, HEAP);
GO

CREATE TABLE stg.fact_sales
(
    transaction_id NVARCHAR(20),
    property_id    NVARCHAR(20),
    agent_id       NVARCHAR(20),
    sale_date_key  INT,
    sale_date      DATE,
    closing_date   DATE,
    financing_type NVARCHAR(30),
    sale_price     DECIMAL(18, 2),
    price_per_sqft DECIMAL(18, 2),
    days_to_close  INT
)
WITH (DISTRIBUTION = ROUND_ROBIN, HEAP);
GO

CREATE TABLE stg.fact_leases
(
    lease_id             NVARCHAR(20),
    property_id          NVARCHAR(20),
    agent_id             NVARCHAR(20),
    lease_start_date_key INT,
    lease_start          DATE,
    lease_end            DATE,
    monthly_rent         DECIMAL(12, 2),
    lease_term_months    INT,
    annualized_rent      DECIMAL(18, 2)
)
WITH (DISTRIBUTION = ROUND_ROBIN, HEAP);
GO

CREATE TABLE stg.fact_listings
(
    listing_id      NVARCHAR(20),
    property_id     NVARCHAR(20),
    agent_id        NVARCHAR(20),
    listed_date_key INT,
    listed_at       DATETIME2,
    status          NVARCHAR(20),
    list_price      DECIMAL(18, 2),
    days_on_market  INT
)
WITH (DISTRIBUTION = ROUND_ROBIN, HEAP);
GO

CREATE TABLE stg.agg_market_monthly
(
    city               NVARCHAR(100),
    state              NCHAR(2),
    [month]            DATE,
    sales_count        BIGINT,
    total_volume       DECIMAL(18, 2),
    median_sale_price  DECIMAL(18, 2),
    avg_price_per_sqft DECIMAL(18, 2),
    avg_days_to_close  DECIMAL(9, 1)
)
WITH (DISTRIBUTION = ROUND_ROBIN, HEAP);
GO
