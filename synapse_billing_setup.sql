-- ========================================================
-- SYNAPSE BILLING DATA SETUP (Manual Backup)
-- ========================================================
-- Auto-generated on: Tue Aug 19 18:17:43 IDT 2025
-- This is a backup if automated setup fails
-- Run this in Synapse Studio connected to Built-in serverless SQL pool
-- Workspace: wiv-synapse-billing-16098
-- Storage Account: billingstorage16060
-- Container: billing-exports

CREATE DATABASE BillingAnalytics;
GO
USE BillingAnalytics;
GO

CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd3919f84e!';
GO

-- Create database user for the service principal
CREATE USER [52e9e7c8-5e81-4cc6-81c1-f8931a008f3f] FROM EXTERNAL PROVIDER;
GO

-- Grant necessary permissions
ALTER ROLE db_datareader ADD MEMBER [52e9e7c8-5e81-4cc6-81c1-f8931a008f3f];
ALTER ROLE db_datawriter ADD MEMBER [52e9e7c8-5e81-4cc6-81c1-f8931a008f3f];
ALTER ROLE db_ddladmin ADD MEMBER [52e9e7c8-5e81-4cc6-81c1-f8931a008f3f];
GO

-- Improved view that automatically queries only the latest export file
-- This prevents data duplication since each export contains cumulative month-to-date data
-- Using Managed Identity with abfss:// protocol (NEVER EXPIRES!)
-- Storage Configuration:
--   Account: billingstorage16060
--   Container: billing-exports
--   Export Path: billing-data
CREATE VIEW BillingData AS
WITH LatestExport AS (
    -- Find the most recent export file
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'abfss://billing-exports@billingstorage16060.dfs.core.windows.net/billing-data/*/*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        FIRSTROW = 2
    ) AS files
)
SELECT *
FROM OPENROWSET(
    BULK 'abfss://billing-exports@billingstorage16060.dfs.core.windows.net/billing-data/*/*.csv',
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
) AS BillingData
WHERE filepath(1) = (SELECT LatestPath FROM LatestExport);
GO
