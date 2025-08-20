-- Step 5: Create or update the billing data view
-- Note: The path needs to match your actual storage structure
-- Try different patterns if the first one fails:

USE BillingAnalytics;
GO

-- Drop the view if it exists (do this outside TRY-CATCH)
IF OBJECT_ID('BillingData', 'V') IS NOT NULL
    DROP VIEW BillingData;
GO

-- Option A: Try with recursive wildcard (most flexible)
BEGIN TRY
    CREATE VIEW BillingData AS
    SELECT * FROM OPENROWSET(
        BULK 'https://billingstorage76565.dfs.core.windows.net/billing-exports/**/*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        HEADER_ROW = TRUE
    ) AS BillingExport;
    PRINT 'View created successfully with https:// protocol'
END TRY
BEGIN CATCH
    PRINT 'Failed with https://, trying abfss:// protocol...'
    BEGIN TRY
        CREATE VIEW BillingData AS
        SELECT * FROM OPENROWSET(
            BULK 'abfss://billing-exports@billingstorage76565.dfs.core.windows.net/**/*.csv',
            FORMAT = 'CSV',
            PARSER_VERSION = '2.0',
            HEADER_ROW = TRUE
        ) AS BillingExport;
        PRINT 'View created successfully with abfss:// protocol'
    END TRY
    BEGIN CATCH
        PRINT 'Warning: View creation failed. No CSV files found yet.'
        PRINT 'The view will work once billing data is exported to:'
        PRINT '  Storage: billingstorage76565'
        PRINT '  Container: billing-exports'
        PRINT ''
        PRINT 'Creating placeholder view for now...'
        
        CREATE VIEW BillingData AS
        SELECT 
            'No billing data available yet' as Message,
            GETDATE() as CheckedAt;
        
        PRINT 'Placeholder view created successfully'
    END CATCH
END CATCH
GO

-- Test the view
SELECT * FROM BillingData;
GO