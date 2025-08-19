-- Manual Fix for Synapse Database and View
-- Run this in Synapse Studio: https://web.azuresynapse.net
-- Workspace: wiv-synapse-billing-35674

-- Step 1: Create Database (run in master database)
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics')
    CREATE DATABASE BillingAnalytics;
GO

-- Step 2: Switch to BillingAnalytics database
USE BillingAnalytics;
GO

-- Step 3: Create Master Key
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd2024!';
GO

-- Step 4: Create User for Service Principal
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account')
    CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
GO

-- Step 5: Grant Permissions
ALTER ROLE db_datareader ADD MEMBER [wiv_account];
ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
GO

-- Step 6: Create BillingData View (using Managed Identity with abfss protocol)
CREATE OR ALTER VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK 'abfss://billing-exports@billingstorage35639.dfs.core.windows.net/billing-data/*/*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport;
GO

-- Step 7: Test the view
SELECT TOP 10 * FROM BillingData;
GO

-- If Step 6 fails, try this alternative with https protocol:
CREATE OR ALTER VIEW BillingDataHTTPS AS
SELECT *
FROM OPENROWSET(
    BULK 'https://billingstorage35639.blob.core.windows.net/billing-exports/billing-data/*/*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport;
GO