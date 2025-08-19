-- ======================================================================
-- SETUP STORAGE ACCESS FOR SYNAPSE
-- Run this in Synapse Studio in the BillingAnalytics database
-- ======================================================================

-- Step 1: Create master key if not exists (already done)
-- CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd2024!';
-- GO

-- Step 2: Create database scoped credential for Managed Identity
CREATE DATABASE SCOPED CREDENTIAL BillingStorageCredential
WITH IDENTITY = 'Managed Identity';
GO

-- Step 3: Create external data source
CREATE EXTERNAL DATA SOURCE BillingExportStorage
WITH (
    TYPE = BLOB_STORAGE,
    LOCATION = 'https://wivcostexports.blob.core.windows.net/billing-exports',
    CREDENTIAL = BillingStorageCredential
);
GO

-- Step 4: Create the view using the external data source
-- This pattern will automatically include all month folders
CREATE OR ALTER VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK 'billing-data/DailyBillingExport/*/*.csv',
    DATA_SOURCE = 'BillingExportStorage',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport;
GO

-- Test the view
SELECT COUNT(*) as TotalRows FROM BillingData;
GO

-- Get sample data
SELECT TOP 10 * FROM BillingData;
GO

-- ======================================================================
-- ALTERNATIVE: If Managed Identity doesn't work, use SAS token
-- ======================================================================
/*
-- Step 1: Get a SAS token from the storage account
-- In Azure Portal: Storage Account > Shared access signature > Generate SAS

-- Step 2: Create credential with SAS token
CREATE DATABASE SCOPED CREDENTIAL BillingStorageSAS
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
SECRET = 'YOUR_SAS_TOKEN_HERE';  -- Don't include the ? at the beginning
GO

-- Step 3: Create external data source with SAS
CREATE EXTERNAL DATA SOURCE BillingExportStorageSAS
WITH (
    TYPE = BLOB_STORAGE,
    LOCATION = 'https://wivcostexports.blob.core.windows.net/billing-exports',
    CREDENTIAL = BillingStorageSAS
);
GO

-- Step 4: Create view using SAS-authenticated data source
CREATE OR ALTER VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK 'billing-data/DailyBillingExport/*/*.csv',
    DATA_SOURCE = 'BillingExportStorageSAS',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport;
GO
*/

-- ======================================================================
-- NOTES:
-- ======================================================================
-- The path pattern 'billing-data/DailyBillingExport/*/*.csv' will:
-- - Match all date range folders (20250801-20250831, 20250901-20250930, etc.)
-- - Match all CSV files within those folders
-- - Automatically include new months as they are added
-- 
-- Requirements for this to work:
-- 1. Synapse workspace managed identity needs "Storage Blob Data Reader" 
--    role on the storage account
-- 2. Or use a SAS token with read permissions
-- ======================================================================