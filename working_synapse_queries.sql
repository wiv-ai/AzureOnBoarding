-- ============================================
-- WORKING SYNAPSE QUERIES FOR YOUR BILLING DATA
-- ============================================
-- Files found in your storage:
-- - DailyBillingExport_b25100c0-b66f-4391-ae32-2661f9e8e729.csv
-- - DailyBillingExport_d6a0aeec-2a67-4a71-a9e4-4a6258720414.csv
-- ============================================

-- 1. Query ALL billing data from your storage
SELECT * 
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData;

-- 2. Get latest 100 records
SELECT TOP 100 *
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
ORDER BY Date DESC;

-- 3. Daily cost summary
SELECT 
    CAST(Date AS DATE) as BillingDate,
    SUM(TRY_CAST(CostInUSD AS FLOAT)) as TotalCostUSD,
    COUNT(*) as TransactionCount
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
GROUP BY CAST(Date AS DATE)
ORDER BY BillingDate DESC;

-- 4. Cost by Service Family
SELECT 
    ServiceFamily,
    SUM(TRY_CAST(CostInUSD AS FLOAT)) as TotalCostUSD,
    COUNT(*) as RecordCount
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
GROUP BY ServiceFamily
ORDER BY TotalCostUSD DESC;

-- 5. Cost by Resource Group
SELECT 
    ResourceGroup,
    SUM(TRY_CAST(CostInUSD AS FLOAT)) as TotalCostUSD,
    COUNT(DISTINCT ResourceId) as ResourceCount
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
WHERE ResourceGroup IS NOT NULL
GROUP BY ResourceGroup
ORDER BY TotalCostUSD DESC;

-- 6. Query specific date range (adjust dates as needed)
SELECT *
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
WHERE CAST(Date AS DATE) BETWEEN '2025-08-01' AND '2025-08-14';

-- 7. Top 10 most expensive resources
SELECT TOP 10
    ResourceId,
    ResourceGroup,
    ServiceFamily,
    SUM(TRY_CAST(CostInUSD AS FLOAT)) as TotalCostUSD
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
WHERE ResourceId IS NOT NULL
GROUP BY ResourceId, ResourceGroup, ServiceFamily
ORDER BY TotalCostUSD DESC;

-- 8. Check which files are being read
SELECT DISTINCT
    filepath(1) as FileName,
    COUNT(*) as RowCount
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
GROUP BY filepath(1);