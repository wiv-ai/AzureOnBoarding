-- Alternative Authentication Setup for Synapse
-- Run this in BillingAnalytics database

-- Method 1: Try creating user with the display name
-- Sometimes the service principal is registered with its display name
BEGIN TRY
    CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
    PRINT 'Created user: wiv_account'
END TRY
BEGIN CATCH
    PRINT 'Could not create wiv_account: ' + ERROR_MESSAGE()
END CATCH
GO

-- Method 2: Create a contained database user with password
-- This bypasses Azure AD and uses SQL authentication
CREATE USER [billing_reader] WITH PASSWORD = 'BillingP@ss2024!';
GO

ALTER ROLE db_datareader ADD MEMBER [billing_reader];
ALTER ROLE db_datawriter ADD MEMBER [billing_reader];
ALTER ROLE db_ddladmin ADD MEMBER [billing_reader];
GO

PRINT 'Created SQL user: billing_reader with password: BillingP@ss2024!'
GO

-- Method 3: Check what users already exist
SELECT 
    name,
    type_desc,
    authentication_type_desc,
    create_date
FROM sys.database_principals
WHERE type NOT IN ('R', 'A', 'G')  -- Exclude roles, app roles, and Windows groups
ORDER BY create_date DESC;
GO

-- Method 4: Try with email format (if service principal has one)
-- CREATE USER [wiv_account@yourdomain.com] FROM EXTERNAL PROVIDER;

-- Show current user context
SELECT 
    SUSER_NAME() as CurrentLogin,
    USER_NAME() as CurrentUser,
    DB_NAME() as CurrentDatabase;