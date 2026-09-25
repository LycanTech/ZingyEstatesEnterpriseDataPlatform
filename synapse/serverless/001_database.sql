-- Run against: master (serverless SQL endpoint)
-- UTF-8 BIN2 collation gives correct string handling and predicate pushdown on Parquet/Delta.
IF DB_ID('zingy_lakehouse') IS NULL
    CREATE DATABASE zingy_lakehouse COLLATE Latin1_General_100_BIN2_UTF8;
GO
