-- ========================================================
-- FINAL SOLUTION FOR SYNAPSE BILLING QUERY
-- ========================================================

-- ⚠️ IMPORTANT: Make sure you are connected to:
--    • Workspace: wiv-synapse-billing
--    • Database: master (or any database)
--    • SQL Pool: Built-in (serverless) - NOT a dedicated pool!

-- ========================================================
-- OPTION 1: QUERY WITH SAS TOKEN (MOST LIKELY TO WORK)
-- ========================================================
-- This includes a SAS token that bypasses all permission issues
-- Valid until: 2025-08-21

SELECT TOP 100 *
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing.csv?se=2025-08-21T14%3A17Z&sp=r&sv=2022-11-02&sr=b&sig=J%2FnAgPUSHaOCGKwfiqTij3wLleNOEnepjEto2YFoMvc%3D',
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
-- OPTION 2: CREATE CREDENTIAL FIRST (RUN THIS ONCE)
-- ========================================================
-- If Option 1 doesn't work, try creating a credential first

-- Step 1: Create a SAS credential
CREATE DATABASE SCOPED CREDENTIAL BillingSASCredential
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
SECRET = 'se=2025-08-21T14%3A17Z&sp=r&sv=2022-11-02&sr=b&sig=J%2FnAgPUSHaOCGKwfiqTij3wLleNOEnepjEto2YFoMvc%3D';

-- Step 2: Create external data source
CREATE EXTERNAL DATA SOURCE BillingStorage
WITH (
    TYPE = BLOB_STORAGE,
    LOCATION = 'https://billingstorage77626.blob.core.windows.net/billing-exports',
    CREDENTIAL = BillingSASCredential
);

-- Step 3: Query using the external data source
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
-- DAILY COST SUMMARY (Using SAS Token)
-- ========================================================
SELECT 
    CAST(date AS DATE) as BillingDate,
    SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as DailyCostUSD,
    COUNT(*) as TransactionCount
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing.csv?se=2025-08-21T14%3A17Z&sp=r&sv=2022-11-02&sr=b&sig=J%2FnAgPUSHaOCGKwfiqTij3wLleNOEnepjEto2YFoMvc%3D',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    date NVARCHAR(100),
    costInUsd NVARCHAR(50)
) AS BillingData
WHERE date != 'date'  -- Exclude header if any
GROUP BY CAST(date AS DATE)
ORDER BY BillingDate DESC;

-- ========================================================
-- TROUBLESHOOTING CHECKLIST
-- ========================================================
/*
If you still get "File cannot be opened" error:

1. ✅ Verify you're using Built-in serverless SQL pool (not dedicated)
2. ✅ Check you're in the correct workspace: wiv-synapse-billing
3. ✅ Ensure you have the WITH clause (required for CSV)
4. ✅ Column names are lowercase (date, serviceFamily, costInUsd)
5. ✅ Use FIRSTROW = 2 to skip the header

If none of the above work:

6. Try creating a new database:
   CREATE DATABASE BillingDB;
   GO
   USE BillingDB;
   GO
   -- Then run the queries above

7. Check Synapse Studio notifications for any error details

8. The file IS accessible - we verified:
   - File exists: 18,559 bytes
   - SAS URL works via curl
   - Permissions are set correctly

The issue is likely:
- Synapse workspace configuration
- Network/firewall rules
- Region mismatch (both are in eastus2, so this is OK)
*/

-- ========================================================
-- TEST QUERY - Verify Synapse is working
-- ========================================================
-- Run this first to verify your Synapse connection works:

SELECT 'Synapse is working!' as Status, GETDATE() as CurrentTime;