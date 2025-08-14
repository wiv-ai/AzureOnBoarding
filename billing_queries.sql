-- Query billing data directly from storage (serverless SQL pool)
-- No setup required - just run these queries in Synapse Studio

-- IMPORTANT: Each daily export contains month-to-date data (cumulative)
-- To avoid duplication, query only the latest file or use DISTINCT

-- 1. Get latest billing data (most recent export file)
-- This gets the latest complete dataset without duplication
WITH LatestFile AS (
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'https://billingstorage95541.blob.core.windows.net/billing-exports/billing-data/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS files
)
SELECT * FROM OPENROWSET(
    BULK 'https://billingstorage95541.blob.core.windows.net/billing-exports/billing-data/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
WHERE filepath(1) = (SELECT LatestPath FROM LatestFile)

-- 2. Query specific date range (from latest export)
-- Replace '2024-08-01' and '2024-08-10' with your desired dates
WITH LatestFile AS (
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'https://billingstorage95541.blob.core.windows.net/billing-exports/billing-data/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS files
)
SELECT * FROM OPENROWSET(
    BULK 'https://billingstorage95541.blob.core.windows.net/billing-exports/billing-data/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
WHERE filepath(1) = (SELECT LatestPath FROM LatestFile)
  AND CAST(Date AS DATE) BETWEEN '2024-08-01' AND '2024-08-10'

-- 3. Daily cost summary for specific date range
WITH LatestFile AS (
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'https://billingstorage95541.blob.core.windows.net/billing-exports/billing-data/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS files
)
SELECT 
    CAST(Date AS DATE) as BillingDate,
    ServiceFamily,
    ResourceGroup,
    SUM(CAST(CostInUSD AS FLOAT)) as TotalCostUSD,
    COUNT(DISTINCT ResourceId) as ResourceCount
FROM OPENROWSET(
    BULK 'https://billingstorage95541.blob.core.windows.net/billing-exports/billing-data/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
WHERE filepath(1) = (SELECT LatestPath FROM LatestFile)
  AND CAST(Date AS DATE) BETWEEN DATEADD(day, -7, GETDATE()) AND GETDATE()
GROUP BY CAST(Date AS DATE), ServiceFamily, ResourceGroup
ORDER BY BillingDate DESC

-- 4. Compare costs between two date ranges
WITH LatestFile AS (
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'https://billingstorage95541.blob.core.windows.net/billing-exports/billing-data/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS files
),
CurrentWeek AS (
    SELECT 
        ServiceFamily,
        SUM(CAST(CostInUSD AS FLOAT)) as CurrentCost
    FROM OPENROWSET(
        BULK 'https://billingstorage95541.blob.core.windows.net/billing-exports/billing-data/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS BillingData
    WHERE filepath(1) = (SELECT LatestPath FROM LatestFile)
      AND CAST(Date AS DATE) BETWEEN DATEADD(day, -7, GETDATE()) AND GETDATE()
    GROUP BY ServiceFamily
),
PreviousWeek AS (
    SELECT 
        ServiceFamily,
        SUM(CAST(CostInUSD AS FLOAT)) as PreviousCost
    FROM OPENROWSET(
        BULK 'https://billingstorage95541.blob.core.windows.net/billing-exports/billing-data/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS BillingData
    WHERE filepath(1) = (SELECT LatestPath FROM LatestFile)
      AND CAST(Date AS DATE) BETWEEN DATEADD(day, -14, GETDATE()) AND DATEADD(day, -8, GETDATE())
    GROUP BY ServiceFamily
)
SELECT 
    COALESCE(c.ServiceFamily, p.ServiceFamily) as ServiceFamily,
    ISNULL(p.PreviousCost, 0) as LastWeekCost,
    ISNULL(c.CurrentCost, 0) as ThisWeekCost,
    ISNULL(c.CurrentCost, 0) - ISNULL(p.PreviousCost, 0) as CostChange,
    CASE 
        WHEN p.PreviousCost > 0 
        THEN ((c.CurrentCost - p.PreviousCost) / p.PreviousCost * 100)
        ELSE 0 
    END as PercentChange
FROM CurrentWeek c
FULL OUTER JOIN PreviousWeek p ON c.ServiceFamily = p.ServiceFamily
ORDER BY ThisWeekCost DESC

-- 5. Monthly cost by day (for charting)
WITH LatestFile AS (
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'https://billingstorage95541.blob.core.windows.net/billing-exports/billing-data/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS files
)
SELECT 
    CAST(Date AS DATE) as BillingDate,
    SUM(CAST(CostInUSD AS FLOAT)) as DailyCost,
    SUM(SUM(CAST(CostInUSD AS FLOAT))) OVER (ORDER BY CAST(Date AS DATE)) as CumulativeCost
FROM OPENROWSET(
    BULK 'https://billingstorage95541.blob.core.windows.net/billing-exports/billing-data/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
WHERE filepath(1) = (SELECT LatestPath FROM LatestFile)
  AND MONTH(CAST(Date AS DATE)) = MONTH(GETDATE())
  AND YEAR(CAST(Date AS DATE)) = YEAR(GETDATE())
GROUP BY CAST(Date AS DATE)
ORDER BY BillingDate
