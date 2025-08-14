-- ========================================================
-- COMPLETE SYNAPSE SOLUTION - RUN IN SYNAPSE STUDIO
-- ========================================================
-- IMPORTANT: Connect to Built-in serverless SQL pool
-- Workspace: wiv-synapse-billing

-- ========================================================
-- OPTION 1: CREATE EXTERNAL DATA SOURCE (RECOMMENDED)
-- ========================================================
-- Run these commands step by step

-- Step 1: Create or use a database
CREATE DATABASE IF NOT EXISTS BillingDB;
GO

USE BillingDB;
GO

-- Step 2: Create master key (if not exists)
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd123!';
END
GO

-- Step 3: Create credential with container-level SAS
DROP DATABASE SCOPED CREDENTIAL IF EXISTS BillingCredential;
GO

CREATE DATABASE SCOPED CREDENTIAL BillingCredential
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
SECRET = 'se=2025-09-13T14%3A23Z&sp=rl&sv=2022-11-02&sr=c&sig=4mNum/LPqCmlAp4Cw/PPeRIgx/4u9JmAnMAkrLFWbBc%3D';
GO

-- Step 4: Create external data source
DROP EXTERNAL DATA SOURCE IF EXISTS BillingStorage;
GO

CREATE EXTERNAL DATA SOURCE BillingStorage
WITH (
    TYPE = BLOB_STORAGE,
    LOCATION = 'https://billingstorage77626.blob.core.windows.net/billing-exports',
    CREDENTIAL = BillingCredential
);
GO

-- Step 5: Query using external data source (THIS SHOULD WORK!)
SELECT TOP 100 *
FROM OPENROWSET(
    BULK 'billing.csv',
    DATA_SOURCE = 'BillingStorage',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    date NVARCHAR(100),
    serviceFamily NVARCHAR(100),
    meterCategory NVARCHAR(100),
    resourceGroupName NVARCHAR(100),
    costInUsd NVARCHAR(50)
) AS BillingData;

-- ========================================================
-- OPTION 2: USE MANAGED IDENTITY
-- ========================================================
-- If Option 1 doesn't work, try Managed Identity

-- Create credential for Managed Identity
DROP DATABASE SCOPED CREDENTIAL IF EXISTS WorkspaceIdentity;
GO

CREATE DATABASE SCOPED CREDENTIAL WorkspaceIdentity
WITH IDENTITY = 'Managed Identity';
GO

-- Create data source with Managed Identity
DROP EXTERNAL DATA SOURCE IF EXISTS BillingStorageMI;
GO

CREATE EXTERNAL DATA SOURCE BillingStorageMI
WITH (
    TYPE = BLOB_STORAGE,
    LOCATION = 'https://billingstorage77626.blob.core.windows.net/billing-exports',
    CREDENTIAL = WorkspaceIdentity
);
GO

-- Query with Managed Identity
SELECT TOP 100 *
FROM OPENROWSET(
    BULK 'billing.csv',
    DATA_SOURCE = 'BillingStorageMI',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    date NVARCHAR(100),
    serviceFamily NVARCHAR(100),
    resourceGroupName NVARCHAR(100),
    costInUsd NVARCHAR(50)
) AS BillingData;

-- ========================================================
-- DAILY COST SUMMARY (After setting up data source)
-- ========================================================
SELECT 
    CAST(date AS DATE) as BillingDate,
    SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as DailyCostUSD,
    COUNT(*) as TransactionCount
FROM OPENROWSET(
    BULK 'billing.csv',
    DATA_SOURCE = 'BillingStorage',  -- Use the data source created above
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    date NVARCHAR(100),
    costInUsd NVARCHAR(50)
) AS BillingData
GROUP BY CAST(date AS DATE)
ORDER BY BillingDate DESC;

-- ========================================================
-- SERVICE COST BREAKDOWN
-- ========================================================
SELECT 
    serviceFamily,
    SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as TotalCostUSD,
    COUNT(*) as TransactionCount
FROM OPENROWSET(
    BULK 'billing.csv',
    DATA_SOURCE = 'BillingStorage',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    serviceFamily NVARCHAR(100),
    costInUsd NVARCHAR(50)
) AS BillingData
GROUP BY serviceFamily
ORDER BY TotalCostUSD DESC;

-- ========================================================
-- TROUBLESHOOTING
-- ========================================================
/*
If you still get errors:

1. Verify you're in Built-in serverless SQL pool (not dedicated)
2. Check the database context (USE BillingDB)
3. Try running each GO statement separately
4. Check Synapse Studio notifications for detailed errors

The file exists and is accessible - we verified:
- Downloaded successfully (18,559 bytes)
- Accessible via curl with SAS token
- Container-level SAS token is valid for 30 days

Common issues:
- Using dedicated SQL pool instead of serverless
- Not running CREATE MASTER KEY first
- Credential already exists with different settings
*/

-- Test connection
SELECT DB_NAME() as CurrentDatabase, @@SERVERNAME as ServerName;