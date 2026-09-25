-- Repeatable. Called by ADF pipeline pl_load_synapse after the Databricks gold step.
--
-- For each table in dw.load_config:
--   1. COPY INTO stg.<table> from gold/_exports/<table>/run_date=<run_date>/*.parquet
--   2. CTAS dw.<table>_new with the configured distribution + clustered columnstore
--   3. Swap dw.<table>_new in with RENAME OBJECT (readers never see a half-loaded table)
-- Dedicated pools do not support cursors, so the loop uses a numbered temp table.

IF OBJECT_ID('dw.usp_load_all', 'P') IS NOT NULL
    DROP PROCEDURE dw.usp_load_all;
GO

CREATE PROCEDURE dw.usp_load_all
    @run_date        NVARCHAR(10),
    @storage_account NVARCHAR(24)
AS
BEGIN
    SET NOCOUNT ON;

    IF TRY_CONVERT(DATE, @run_date, 23) IS NULL
        THROW 50001, 'run_date must be YYYY-MM-DD', 1;
    IF @storage_account LIKE '%[^a-z0-9]%' OR LEN(@storage_account) NOT BETWEEN 3 AND 24
        THROW 50002, 'storage_account must be 3-24 lowercase alphanumeric characters', 1;

    IF OBJECT_ID('tempdb..#tables') IS NOT NULL
        DROP TABLE #tables;

    CREATE TABLE #tables
    WITH (DISTRIBUTION = ROUND_ROBIN)
    AS
    SELECT ROW_NUMBER() OVER (ORDER BY load_order) AS seq, table_name, distribution
    FROM dw.load_config
    WHERE enabled = 1;

    DECLARE @i INT = 1,
            @n INT = (SELECT COUNT(*) FROM #tables),
            @table SYSNAME,
            @dist NVARCHAR(200),
            @started DATETIME2,
            @rows BIGINT,
            @sql NVARCHAR(4000);

    WHILE @i <= @n
    BEGIN
        SELECT @table = table_name, @dist = distribution FROM #tables WHERE seq = @i;
        SET @started = SYSUTCDATETIME();

        SET @sql = N'TRUNCATE TABLE stg.' + QUOTENAME(@table) + N';';
        EXEC sp_executesql @sql;

        SET @sql = N'COPY INTO stg.' + QUOTENAME(@table)
                 + N' FROM ''https://' + @storage_account + N'.dfs.core.windows.net/gold/_exports/'
                 + @table + N'/run_date=' + @run_date + N'/*.parquet'''
                 + N' WITH (FILE_TYPE = ''PARQUET'', CREDENTIAL = (IDENTITY = ''Managed Identity''));';
        EXEC sp_executesql @sql;

        SET @sql = N'IF OBJECT_ID(''dw.' + @table + N'_new'') IS NOT NULL DROP TABLE dw.' + QUOTENAME(@table + N'_new') + N';'
                 + N' CREATE TABLE dw.' + QUOTENAME(@table + N'_new')
                 + N' WITH (' + @dist + N', CLUSTERED COLUMNSTORE INDEX)'
                 + N' AS SELECT * FROM stg.' + QUOTENAME(@table) + N';';
        EXEC sp_executesql @sql;

        SET @sql = N'IF OBJECT_ID(''dw.' + @table + N''') IS NOT NULL RENAME OBJECT dw.' + QUOTENAME(@table) + N' TO ' + QUOTENAME(@table + N'_old') + N';'
                 + N' RENAME OBJECT dw.' + QUOTENAME(@table + N'_new') + N' TO ' + QUOTENAME(@table) + N';'
                 + N' IF OBJECT_ID(''dw.' + @table + N'_old'') IS NOT NULL DROP TABLE dw.' + QUOTENAME(@table + N'_old') + N';';
        EXEC sp_executesql @sql;

        SET @sql = N'SELECT @c = COUNT_BIG(*) FROM dw.' + QUOTENAME(@table) + N';';
        EXEC sp_executesql @sql, N'@c BIGINT OUTPUT', @c = @rows OUTPUT;

        INSERT INTO dw.load_audit (run_date, table_name, row_count, started_at, finished_at)
        VALUES (CONVERT(DATE, @run_date, 23), @table, @rows, @started, SYSUTCDATETIME());

        SET @i = @i + 1;
    END
END;
GO
