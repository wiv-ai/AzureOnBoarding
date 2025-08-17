-- ========================================================
-- BILLING DATA QUERIES - OPTIMIZED VERSION
-- ========================================================
-- The BillingData view now AUTOMATICALLY prevents duplication!
-- No need for complex CTE patterns - just query the view directly
--
-- Background: Each daily export contains cumulative month-to-date data
-- The improved view automatically filters to only the latest export file
-- This means you get accurate, non-duplicated data with simple queries
-- ========================================================

-- 1. Simple query - automatically gets latest data without duplication
SELECT * FROM BillingAnalytics.dbo.BillingData
WHERE CAST(Date AS DATE) >= DATEADD(day, -7, GETDATE())

-- 2. Query specific date range
-- Replace '2024-08-01' and '2024-08-10' with your desired dates
SELECT * FROM BillingAnalytics.dbo.BillingData
WHERE CAST(Date AS DATE) BETWEEN '2024-08-01' AND '2024-08-10'

-- 3. Daily cost summary for last 7 days
SELECT 
    CAST(Date AS DATE) as BillingDate,
    ServiceFamily,
    ResourceGroupName,
    SUM(CAST(CostInUSD AS FLOAT)) as TotalCostUSD,
    COUNT(DISTINCT ResourceId) as ResourceCount
FROM BillingAnalytics.dbo.BillingData
WHERE CAST(Date AS DATE) BETWEEN DATEADD(day, -7, GETDATE()) AND GETDATE()
GROUP BY CAST(Date AS DATE), ServiceFamily, ResourceGroupName
ORDER BY BillingDate DESC

-- 4. Compare costs between two date ranges
WITH CurrentWeek AS (
    SELECT 
        ServiceFamily,
        SUM(CAST(CostInUSD AS FLOAT)) as CurrentCost
    FROM BillingAnalytics.dbo.BillingData
    WHERE CAST(Date AS DATE) BETWEEN DATEADD(day, -7, GETDATE()) AND GETDATE()
    GROUP BY ServiceFamily
),
PreviousWeek AS (
    SELECT 
        ServiceFamily,
        SUM(CAST(CostInUSD AS FLOAT)) as PreviousCost
    FROM BillingAnalytics.dbo.BillingData
    WHERE CAST(Date AS DATE) BETWEEN DATEADD(day, -14, GETDATE()) AND DATEADD(day, -8, GETDATE())
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
SELECT 
    CAST(Date AS DATE) as BillingDate,
    SUM(CAST(CostInUSD AS FLOAT)) as DailyCost,
    SUM(SUM(CAST(CostInUSD AS FLOAT))) OVER (ORDER BY CAST(Date AS DATE)) as CumulativeCost
FROM BillingAnalytics.dbo.BillingData
WHERE MONTH(CAST(Date AS DATE)) = MONTH(GETDATE())
  AND YEAR(CAST(Date AS DATE)) = YEAR(GETDATE())
GROUP BY CAST(Date AS DATE)
ORDER BY BillingDate
