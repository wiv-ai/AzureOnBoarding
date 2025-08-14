-- ========================================================
-- SYNAPSE BILLING DATA SETUP
-- ========================================================
-- Run this in Synapse Studio connected to Built-in serverless SQL pool
-- Workspace: wiv-synapse-billing

-- Step 1: Create database (drop if exists for clean setup)
-- Note: Comment out the DROP if you want to preserve existing database
-- DROP DATABASE IF EXISTS BillingAnalytics;
-- GO

CREATE DATABASE BillingAnalytics;
GO

USE BillingAnalytics;
GO

-- Step 2: Create master key (required for credentials)
-- If it already exists, comment this out
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd123!';
GO

-- Step 3: Drop existing credential if it exists (for clean setup)
-- Note: This SAS token is valid for 30 days from creation
IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'BillingStorageCredential')
    DROP DATABASE SCOPED CREDENTIAL BillingStorageCredential;
GO

CREATE DATABASE SCOPED CREDENTIAL BillingStorageCredential
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
SECRET = 'se=2025-09-13T14%3A23Z&sp=rl&sv=2022-11-02&sr=c&sig=4mNum/LPqCmlAp4Cw/PPeRIgx/4u9JmAnMAkrLFWbBc%3D';
GO

-- Step 4: Drop existing data source if it exists
IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'BillingDataSource')
    DROP EXTERNAL DATA SOURCE BillingDataSource;
GO

CREATE EXTERNAL DATA SOURCE BillingDataSource
WITH (
    LOCATION = 'https://billingstorage77626.blob.core.windows.net/billing-exports',
    CREDENTIAL = BillingStorageCredential
);
GO

-- Step 5: Create a view for easy querying
-- Using NVARCHAR to handle UTF8 encoding properly
IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingData')
    DROP VIEW BillingData;
GO

CREATE VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK 'billing-data/DailyBillingExport/20250801-20250831/*.csv',
    DATA_SOURCE = 'BillingDataSource',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    date NVARCHAR(100),
    serviceFamily NVARCHAR(200),
    meterCategory NVARCHAR(200),
    meterSubCategory NVARCHAR(200),
    meterName NVARCHAR(500),
    billingAccountName NVARCHAR(200),
    costCenter NVARCHAR(100),
    resourceGroupName NVARCHAR(200),
    resourceLocation NVARCHAR(100),
    consumedService NVARCHAR(200),
    ResourceId NVARCHAR(1000),
    chargeType NVARCHAR(100),
    publisherType NVARCHAR(100),
    quantity NVARCHAR(100),
    costInBillingCurrency NVARCHAR(100),
    costInUsd NVARCHAR(100),
    PayGPrice NVARCHAR(100),
    billingCurrency NVARCHAR(10),
    subscriptionName NVARCHAR(200),
    SubscriptionId NVARCHAR(100),
    ProductName NVARCHAR(500),
    frequency NVARCHAR(100),
    unitOfMeasure NVARCHAR(100),
    tags NVARCHAR(4000)
) AS BillingData;
GO

-- Step 6: Create additional views for common queries
-- View for current month's data
CREATE VIEW CurrentMonthBilling AS
SELECT *
FROM OPENROWSET(
    BULK 'billing-data/DailyBillingExport/20250801-20250831/*.csv',
    DATA_SOURCE = 'BillingDataSource',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    date NVARCHAR(100),
    serviceFamily NVARCHAR(200),
    resourceGroupName NVARCHAR(200),
    costInUsd NVARCHAR(100)
) AS BillingData
WHERE date IS NOT NULL AND date != 'date';
GO

-- ========================================================
-- SAMPLE QUERIES
-- ========================================================

-- Query 1: Test the view
SELECT TOP 10 * FROM BillingData;

-- Query 2: Daily cost summary
SELECT 
    CAST(date AS DATE) as BillingDate,
    SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as TotalCostUSD,
    COUNT(*) as TransactionCount
FROM BillingData
WHERE date IS NOT NULL AND date != 'date'
GROUP BY CAST(date AS DATE)
ORDER BY BillingDate DESC;

-- Query 3: Cost by service family
SELECT 
    serviceFamily,
    SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as TotalCostUSD,
    COUNT(*) as TransactionCount
FROM BillingData
WHERE serviceFamily IS NOT NULL
GROUP BY serviceFamily
ORDER BY TotalCostUSD DESC;

-- Query 4: Cost by resource group
SELECT 
    resourceGroupName,
    SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as TotalCostUSD,
    COUNT(DISTINCT ResourceId) as ResourceCount
FROM BillingData
WHERE resourceGroupName IS NOT NULL
GROUP BY resourceGroupName
ORDER BY TotalCostUSD DESC;

-- Query 5: Monthly cost trend
SELECT 
    YEAR(TRY_CAST(date AS DATE)) as Year,
    MONTH(TRY_CAST(date AS DATE)) as Month,
    SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as MonthlyCostUSD
FROM BillingData
WHERE date IS NOT NULL AND date != 'date'
GROUP BY YEAR(TRY_CAST(date AS DATE)), MONTH(TRY_CAST(date AS DATE))
ORDER BY Year DESC, Month DESC;

-- Query 6: Direct OPENROWSET query (if view doesn't work)
-- This can be used directly without creating the view
SELECT TOP 100 *
FROM OPENROWSET(
    BULK 'billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
    DATA_SOURCE = 'BillingDataSource',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    date NVARCHAR(100),
    serviceFamily NVARCHAR(200),
    meterCategory NVARCHAR(200),
    resourceGroupName NVARCHAR(200),
    costInUsd NVARCHAR(100)
) AS BillingData;