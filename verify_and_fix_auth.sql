-- First, let's check what authentication is available
-- Run this in BillingAnalytics database

-- Check if we can use a different authentication method
-- Option 1: Try with the app name instead of GUID
CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
GO

-- If that fails, try Option 2: Create a SQL user with password
-- This is a fallback if Azure AD isn't working
/*
CREATE USER [synapse_user] WITH PASSWORD = 'StrongP@ssw0rd2024!';
GO

ALTER ROLE db_datareader ADD MEMBER [synapse_user];
ALTER ROLE db_datawriter ADD MEMBER [synapse_user];
ALTER ROLE db_ddladmin ADD MEMBER [synapse_user];
GO
*/

-- Option 3: Check if the service principal exists in Azure AD
-- This query shows all external users
SELECT name, type_desc, authentication_type_desc 
FROM sys.database_principals 
WHERE type IN ('E', 'X');

-- Option 4: Grant permissions to the Synapse workspace managed identity
-- The workspace itself has a managed identity that can be used
-- Find the workspace managed identity name (usually same as workspace name)
-- CREATE USER [wiv-synapse-billing] FROM EXTERNAL PROVIDER;
-- GO
-- ALTER ROLE db_datareader ADD MEMBER [wiv-synapse-billing];
-- GO