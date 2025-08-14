-- ============================================
-- SYNAPSE BILLING QUERIES - READY TO USE
-- ============================================
-- Workspace: wiv-synapse-billing
-- Storage: billingstorage73919
-- Container: billing-exports
-- 
-- Instructions:
-- 1. Open https://web.azuresynapse.net
-- 2. Select workspace: wiv-synapse-billing
-- 3. Go to Develop > SQL scripts > New
-- 4. Connect to: Built-in (serverless pool)
-- 5. Run these queries
-- ============================================

-- TEST 1: Check if billing data exists
SELECT TOP 10 
    *
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/billing-data/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData;

-- TEST 2: Get latest costs (if data exists)
SELECT TOP 100
    Date,
    ServiceFamily,
    ResourceGroup,
    CAST(CostInUSD AS FLOAT) as CostUSD,
    SubscriptionName
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/billing-data/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
ORDER BY Date DESC;

-- TEST 3: Daily cost summary (last 7 days)
SELECT 
    CAST(Date AS DATE) as BillingDate,
    SUM(CAST(CostInUSD AS FLOAT)) as TotalCostUSD,
    COUNT(*) as TransactionCount
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/billing-data/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
WHERE CAST(Date AS DATE) >= DATEADD(day, -7, GETDATE())
GROUP BY CAST(Date AS DATE)
ORDER BY BillingDate DESC;

-- TEST 4: Cost by Service
SELECT 
    ServiceFamily,
    SUM(CAST(CostInUSD AS FLOAT)) as TotalCostUSD,
    COUNT(DISTINCT ResourceId) as ResourceCount
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/billing-data/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
GROUP BY ServiceFamily
ORDER BY TotalCostUSD DESC;

-- TEST 5: Check what files are available (using filepath function)
SELECT DISTINCT
    filepath(1) as FileName,
    COUNT(*) as RowCount
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/billing-data/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
GROUP BY filepath(1);

-- If you get an error about "no files found", it means:
-- 1. The billing export hasn't run yet (runs daily)
-- 2. You can trigger it manually from Azure Portal > Cost Management > Exports
-- 3. Or wait for the daily schedule to run