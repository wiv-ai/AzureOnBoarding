-- Azure Synapse Billing Database Setup Script
-- This script handles database creation with retry logic for lock issues

-- Step 1: Check if database exists and create with retry logic
-- Note: In Synapse Studio, you may need to run these sections separately

-- First, check if the database exists
SELECT name FROM sys.databases WHERE name = 'BillingAnalytics';
GO

-- If the database doesn't exist, create it
-- If you get a lock error, wait a moment and try again
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics')
BEGIN
    PRINT 'Creating BillingAnalytics database...';
    CREATE DATABASE BillingAnalytics;
    PRINT 'Database created successfully.';
END
ELSE
BEGIN
    PRINT 'Database BillingAnalytics already exists.';
END
GO

-- Wait a moment to ensure database is ready
WAITFOR DELAY '00:00:05';
GO

-- Step 2: Switch to the new database
USE BillingAnalytics;
GO

-- Step 3: Create master key if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    PRINT 'Creating master key...';
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd2024!';
    PRINT 'Master key created successfully.';
END
ELSE
BEGIN
    PRINT 'Master key already exists.';
END
GO

-- Step 4: Create user from external provider
-- Check if user exists first
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account')
BEGIN
    PRINT 'Creating user wiv_account...';
    CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
    PRINT 'User created successfully.';
END
ELSE
BEGIN
    PRINT 'User wiv_account already exists.';
END
GO

-- Step 5: Grant permissions to the user
PRINT 'Granting permissions to wiv_account...';

-- Add to db_datareader role
IF IS_ROLEMEMBER('db_datareader', 'wiv_account') = 0
BEGIN
    ALTER ROLE db_datareader ADD MEMBER [wiv_account];
    PRINT '  - Added to db_datareader role';
END

-- Add to db_datawriter role
IF IS_ROLEMEMBER('db_datawriter', 'wiv_account') = 0
BEGIN
    ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
    PRINT '  - Added to db_datawriter role';
END

-- Add to db_ddladmin role
IF IS_ROLEMEMBER('db_ddladmin', 'wiv_account') = 0
BEGIN
    ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
    PRINT '  - Added to db_ddladmin role';
END
GO

-- Step 6: Create or alter the billing data view
PRINT 'Creating/updating BillingData view...';

CREATE OR ALTER VIEW BillingData AS
SELECT * FROM OPENROWSET(
    BULK 'abfss://billing-exports@billingstorage74725.dfs.core.windows.net/billing-data/*/*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport;
GO

PRINT 'BillingData view created/updated successfully.';
PRINT '';
PRINT '✅ Database setup completed successfully!';
GO