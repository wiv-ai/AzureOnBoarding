-- Fix the BillingData view with the correct storage path
-- Run this in Synapse Studio connected to the BillingAnalytics database

USE BillingAnalytics;
GO

-- Drop the existing view if it exists
IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingData')
    DROP VIEW BillingData;
GO

-- Create the view with the correct storage path
-- Note: You need to verify the actual container name and path in your storage account
CREATE VIEW BillingData AS
SELECT * FROM OPENROWSET(
    BULK 'https://billingstorage74725.dfs.core.windows.net/billing-exports/billing-data/**/*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport;
GO

-- Test the view
SELECT TOP 10 * FROM BillingData;
GO