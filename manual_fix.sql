-- Run this in Synapse Studio
-- Connect to: wiv-synapse-billing-24895
-- https://web.azuresynapse.net

-- Step 1: Create database if not exists
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics')
    CREATE DATABASE BillingAnalytics;
GO

-- Step 2: Switch to the database
USE BillingAnalytics;
GO

-- Step 3: Create master key (required for external tables)
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd2024!';
GO

-- Step 4: Create user for the service principal
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account')
    CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
GO

-- Step 5: Grant permissions
ALTER ROLE db_datareader ADD MEMBER [wiv_account];
ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
GO

-- Step 6: Verify
SELECT 'Database setup complete!' as Status;
GO