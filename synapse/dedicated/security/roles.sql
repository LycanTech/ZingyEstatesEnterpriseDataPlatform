-- Repeatable. sqlcmd variables:
--   $(AdfName)            - Data Factory name (its managed identity runs dw.usp_load_all)
--   $(ReportingGroupName) - Entra ID group for Power BI / analysts

IF DATABASE_PRINCIPAL_ID('etl_loader') IS NULL
    CREATE ROLE etl_loader;
GO
IF DATABASE_PRINCIPAL_ID('reporting_reader') IS NULL
    CREATE ROLE reporting_reader;
GO

-- dw.usp_load_all runs dynamic SQL, so ownership chaining does not apply and the
-- caller needs the underlying permissions.
GRANT EXECUTE ON dw.usp_load_all TO etl_loader;
GRANT ADMINISTER DATABASE BULK OPERATIONS TO etl_loader;
GRANT CREATE TABLE TO etl_loader;
GRANT ALTER, SELECT, INSERT ON SCHEMA::stg TO etl_loader;
GRANT ALTER, SELECT, INSERT ON SCHEMA::dw TO etl_loader;
GO

GRANT SELECT ON SCHEMA::dw TO reporting_reader;
GO

IF DATABASE_PRINCIPAL_ID('$(AdfName)') IS NULL
    CREATE USER [$(AdfName)] FROM EXTERNAL PROVIDER;
GO
EXEC sp_addrolemember 'etl_loader', '$(AdfName)';
GO

IF DATABASE_PRINCIPAL_ID('$(ReportingGroupName)') IS NULL
    CREATE USER [$(ReportingGroupName)] FROM EXTERNAL PROVIDER;
GO
EXEC sp_addrolemember 'reporting_reader', '$(ReportingGroupName)';
GO
