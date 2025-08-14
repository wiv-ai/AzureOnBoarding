-- ========================================================
-- SYNAPSE EXTERNAL TABLE SETUP FOR BILLING DATA
-- ========================================================
-- Run this in Synapse Studio connected to Built-in serverless SQL pool
-- Workspace: wiv-synapse-billing

-- Step 1: Create or use a database
CREATE DATABASE IF NOT EXISTS BillingAnalytics;
GO

USE BillingAnalytics;
GO

-- Step 2: Create master key (required for credentials)
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd123!';
END
GO

-- Step 3: Create database scoped credential with SAS token
-- Note: This SAS token is valid for 30 days from creation
DROP DATABASE SCOPED CREDENTIAL IF EXISTS BillingStorageCredential;
GO

CREATE DATABASE SCOPED CREDENTIAL BillingStorageCredential
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
SECRET = 'se=2025-09-13T14%3A23Z&sp=rl&sv=2022-11-02&sr=c&sig=4mNum/LPqCmlAp4Cw/PPeRIgx/4u9JmAnMAkrLFWbBc%3D';
GO

-- Step 4: Create external data source pointing to blob storage
DROP EXTERNAL DATA SOURCE IF EXISTS BillingDataSource;
GO

CREATE EXTERNAL DATA SOURCE BillingDataSource
WITH (
    TYPE = HADOOP,
    LOCATION = 'wasbs://billing-exports@billingstorage77626.blob.core.windows.net/',
    CREDENTIAL = BillingStorageCredential
);
GO

-- Step 5: Create external file format for CSV
DROP EXTERNAL FILE FORMAT IF EXISTS BillingCSVFormat;
GO

CREATE EXTERNAL FILE FORMAT BillingCSVFormat
WITH (
    FORMAT_TYPE = DELIMITEDTEXT,
    FORMAT_OPTIONS (
        FIELD_TERMINATOR = ',',
        STRING_DELIMITER = '"',
        FIRST_ROW = 2,
        USE_TYPE_DEFAULT = TRUE
    )
);
GO

-- Step 6: Create external table with correct schema
-- Based on actual CSV columns (lowercase)
DROP EXTERNAL TABLE IF EXISTS BillingData;
GO

CREATE EXTERNAL TABLE BillingData (
    date VARCHAR(100),
    serviceFamily VARCHAR(200),
    meterCategory VARCHAR(200),
    meterSubCategory VARCHAR(200),
    meterName VARCHAR(500),
    billingAccountName VARCHAR(200),
    costCenter VARCHAR(100),
    resourceGroupName VARCHAR(200),
    resourceLocation VARCHAR(100),
    consumedService VARCHAR(200),
    ResourceId VARCHAR(1000),
    chargeType VARCHAR(100),
    publisherType VARCHAR(100),
    quantity VARCHAR(100),
    costInBillingCurrency VARCHAR(100),
    costInUsd VARCHAR(100),
    PayGPrice VARCHAR(100),
    billingCurrency VARCHAR(10),
    subscriptionName VARCHAR(200),
    SubscriptionId VARCHAR(100),
    ProductName VARCHAR(500),
    frequency VARCHAR(100),
    unitOfMeasure VARCHAR(100),
    tags VARCHAR(MAX)
)
WITH (
    LOCATION = '/billing-data/DailyBillingExport/*/*.csv',
    DATA_SOURCE = BillingDataSource,
    FILE_FORMAT = BillingCSVFormat
);
GO

-- ========================================================
-- SAMPLE QUERIES
-- ========================================================

-- Query 1: Test the external table
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