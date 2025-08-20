-- Diagnostic script to check storage paths in Synapse
-- Run this in Synapse Studio connected to the BillingAnalytics database

USE BillingAnalytics;
GO

-- Option 1: Try to list the contents of the container
-- This will show you what's actually in your storage
SELECT * FROM sys.dm_external_data_processed;
GO

-- Option 2: Try different path patterns to find your CSV files
-- Adjust the storage account name if needed

-- Check root of container
BEGIN TRY
    SELECT TOP 1 * FROM OPENROWSET(
        BULK 'https://billingstorage74725.dfs.core.windows.net/billing-exports/*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        HEADER_ROW = TRUE
    ) AS Test1;
    PRINT 'Found CSV files in: billing-exports root'
END TRY
BEGIN CATCH
    PRINT 'No CSV files in: billing-exports root'
END CATCH
GO

-- Check billing-data subfolder
BEGIN TRY
    SELECT TOP 1 * FROM OPENROWSET(
        BULK 'https://billingstorage74725.dfs.core.windows.net/billing-exports/billing-data/*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        HEADER_ROW = TRUE
    ) AS Test2;
    PRINT 'Found CSV files in: billing-exports/billing-data/'
END TRY
BEGIN CATCH
    PRINT 'No CSV files in: billing-exports/billing-data/'
END CATCH
GO

-- Check with recursive wildcard
BEGIN TRY
    SELECT TOP 1 * FROM OPENROWSET(
        BULK 'https://billingstorage74725.dfs.core.windows.net/billing-exports/**/*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        HEADER_ROW = TRUE
    ) AS Test3;
    PRINT 'Found CSV files in: billing-exports (recursive)'
END TRY
BEGIN CATCH
    PRINT 'No CSV files in: billing-exports (recursive)'
END CATCH
GO

-- Alternative: Check if you need to use abfss:// protocol instead
BEGIN TRY
    SELECT TOP 1 * FROM OPENROWSET(
        BULK 'abfss://billing-exports@billingstorage74725.dfs.core.windows.net/**/*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        HEADER_ROW = TRUE
    ) AS Test4;
    PRINT 'Found CSV files using abfss:// protocol'
END TRY
BEGIN CATCH
    PRINT 'No CSV files using abfss:// protocol'
END CATCH
GO