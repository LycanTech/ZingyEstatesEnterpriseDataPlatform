-- Run against: zingy_lakehouse (serverless)
-- sqlcmd variables: $(StorageAccount), $(MasterKeyPassword)
-- The workspace managed identity reads the gold file system; callers never need
-- their own storage permissions.

IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$(MasterKeyPassword)';
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = 'WorkspaceIdentity')
    CREATE DATABASE SCOPED CREDENTIAL WorkspaceIdentity WITH IDENTITY = 'Managed Identity';
GO

IF NOT EXISTS (SELECT 1 FROM sys.external_data_sources WHERE name = 'gold_lake')
    CREATE EXTERNAL DATA SOURCE gold_lake
    WITH (
        LOCATION = 'https://$(StorageAccount).dfs.core.windows.net/gold',
        CREDENTIAL = WorkspaceIdentity
    );
GO

IF SCHEMA_ID('gold') IS NULL
    EXEC ('CREATE SCHEMA gold');
GO
