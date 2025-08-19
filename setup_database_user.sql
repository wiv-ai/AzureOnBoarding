-- ======================================================================
-- SETUP DATABASE USER FOR SERVICE PRINCIPAL
-- Run this in Synapse Studio in the BillingAnalytics database
-- ======================================================================

-- Make sure you're in the BillingAnalytics database
USE BillingAnalytics;
GO

-- Create database user for the service principal (using app name)
CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
GO

-- Grant necessary permissions
ALTER ROLE db_datareader ADD MEMBER [wiv_account];
ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
GO

-- Verify the user was created
SELECT 
    name,
    type_desc,
    authentication_type_desc,
    create_date
FROM sys.database_principals 
WHERE name = 'wiv_account';
GO

-- Check current database
SELECT DB_NAME() as CurrentDatabase;
GO

print 'User wiv_account created successfully with all permissions!';