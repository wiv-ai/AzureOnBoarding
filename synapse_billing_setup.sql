-- ========================================================
-- SYNAPSE BILLING DATA SETUP (Manual Backup)
-- ========================================================
-- Auto-generated on: Sun Aug 17 13:54:12 IDT 2025
-- This is a backup if automated setup fails
-- Run this in Synapse Studio connected to Built-in serverless SQL pool
-- Workspace: wiv-synapse-billing
-- Storage Account: billingstorage26612
-- Container: billing-exports

CREATE DATABASE BillingAnalytics;
GO
USE BillingAnalytics;
GO

CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd75a782af!';
GO

-- Improved view that automatically queries only the latest export file
-- This prevents data duplication since each export contains cumulative month-to-date data
-- Using Managed Identity with abfss:// protocol (NEVER EXPIRES!)
CREATE VIEW BillingData AS
WITH LatestExport AS (
    -- Find the most recent export file
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'abfss://billing-exports@billingstorage26612.dfs.core.windows.net/billing-data/DailyBillingExport/*/*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        FIRSTROW = 2
    ) AS files
)
SELECT *
FROM OPENROWSET(
    BULK 'abfss://billing-exports@billingstorage26612.dfs.core.windows.net/billing-data/DailyBillingExport/*/*.csv',
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
