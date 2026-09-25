-- Run against: zingy_lakehouse (serverless). Repeatable.
-- sqlcmd variables: $(ReportingGroupName) - Entra ID group for Power BI / analysts

IF DATABASE_PRINCIPAL_ID('reporting_reader') IS NULL
    CREATE ROLE reporting_reader;
GO

GRANT SELECT ON SCHEMA::gold TO reporting_reader;
GRANT REFERENCES ON DATABASE SCOPED CREDENTIAL::WorkspaceIdentity TO reporting_reader;
GO

IF DATABASE_PRINCIPAL_ID('$(ReportingGroupName)') IS NULL
    CREATE USER [$(ReportingGroupName)] FROM EXTERNAL PROVIDER;
GO

ALTER ROLE reporting_reader ADD MEMBER [$(ReportingGroupName)];
GO
