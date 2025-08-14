-- ========================================================
-- AZURE SYNAPSE WILDCARD QUERIES FOR BILLING DATA
-- ========================================================
-- These queries use wildcards to automatically pick up all billing export files
-- Connection: Use Built-in serverless SQL pool in Synapse Studio

-- ========================================================
-- WILDCARD PATTERNS EXPLAINED
-- ========================================================
-- Pattern: billing-data/DailyBillingExport/*/DailyBillingExport*.csv
-- This will match:
--   - All date folders (20250801-20250831, 20250901-20250930, etc.)
--   - All export files (DailyBillingExport_*.csv)
-- Benefits:
--   - Automatically includes new daily exports
--   - No need to update queries when new files are added
--   - Can query across multiple billing periods

-- ========================================================
-- QUERY 1: Get Latest Billing Data (All Files)
-- ========================================================
SELECT TOP 1000 *
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    Date NVARCHAR(100),
    ServiceFamily NVARCHAR(100),
    MeterCategory NVARCHAR(100),
    MeterSubcategory NVARCHAR(100),
    MeterName NVARCHAR(200),
    BillingAccountName NVARCHAR(100),
    CostCenter NVARCHAR(50),
    ResourceGroup NVARCHAR(100),
    ResourceLocation NVARCHAR(50),
    ConsumedService NVARCHAR(100),
    ResourceId NVARCHAR(500),
    ChargeType NVARCHAR(50),
    PublisherType NVARCHAR(50),
    Quantity NVARCHAR(50),
    CostInBillingCurrency NVARCHAR(50),
    CostInUSD NVARCHAR(50),
    PayGPrice NVARCHAR(50),
    BillingCurrencyCode NVARCHAR(10),
    SubscriptionName NVARCHAR(100),
    SubscriptionId NVARCHAR(50),
    ProductName NVARCHAR(200),
    Frequency NVARCHAR(50),
    UnitOfMeasure NVARCHAR(50),
    Tags NVARCHAR(MAX)
) AS BillingData
ORDER BY Date DESC;

-- ========================================================
-- QUERY 2: Daily Cost Summary (All Periods)
-- ========================================================
SELECT 
    CAST(Date AS DATE) as BillingDate,
    COUNT(*) as TransactionCount,
    COUNT(DISTINCT ResourceGroup) as UniqueResourceGroups,
    COUNT(DISTINCT ServiceFamily) as UniqueServices,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as DailyCostUSD,
    AVG(TRY_CAST(CostInUSD as DECIMAL(18,2))) as AvgTransactionCost
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    Date NVARCHAR(100),
    ResourceGroup NVARCHAR(100),
    ServiceFamily NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE Date IS NOT NULL
GROUP BY CAST(Date AS DATE)
ORDER BY BillingDate DESC;

-- ========================================================
-- QUERY 3: Service Cost Breakdown (All Time)
-- ========================================================
SELECT 
    ServiceFamily,
    MeterCategory,
    COUNT(*) as TransactionCount,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as TotalCostUSD,
    AVG(TRY_CAST(CostInUSD as DECIMAL(18,2))) as AvgCostPerTransaction,
    MIN(Date) as FirstUsageDate,
    MAX(Date) as LastUsageDate
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    Date NVARCHAR(100),
    ServiceFamily NVARCHAR(100),
    MeterCategory NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE ServiceFamily IS NOT NULL
GROUP BY ServiceFamily, MeterCategory
ORDER BY TotalCostUSD DESC;

-- ========================================================
-- QUERY 4: Resource Group Cost Analysis
-- ========================================================
SELECT 
    ResourceGroup,
    COUNT(DISTINCT ServiceFamily) as ServicesUsed,
    COUNT(*) as TransactionCount,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as TotalCostUSD,
    MIN(Date) as FirstActivity,
    MAX(Date) as LastActivity,
    DATEDIFF(day, MIN(Date), MAX(Date)) + 1 as ActiveDays
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    Date NVARCHAR(100),
    ResourceGroup NVARCHAR(100),
    ServiceFamily NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE ResourceGroup IS NOT NULL AND ResourceGroup != ''
GROUP BY ResourceGroup
ORDER BY TotalCostUSD DESC;

-- ========================================================
-- QUERY 5: Top 20 Most Expensive Resources
-- ========================================================
SELECT TOP 20
    ResourceId,
    ResourceGroup,
    ServiceFamily,
    MeterCategory,
    COUNT(*) as UsageCount,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as TotalCostUSD,
    AVG(TRY_CAST(CostInUSD as DECIMAL(18,2))) as AvgCostPerUsage
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    ResourceId NVARCHAR(500),
    ResourceGroup NVARCHAR(100),
    ServiceFamily NVARCHAR(100),
    MeterCategory NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE ResourceId IS NOT NULL AND ResourceId != ''
GROUP BY ResourceId, ResourceGroup, ServiceFamily, MeterCategory
ORDER BY TotalCostUSD DESC;

-- ========================================================
-- QUERY 6: Location-based Cost Analysis
-- ========================================================
SELECT 
    ResourceLocation,
    COUNT(DISTINCT ResourceGroup) as ResourceGroups,
    COUNT(DISTINCT ServiceFamily) as Services,
    COUNT(*) as TransactionCount,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as TotalCostUSD
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    ResourceLocation NVARCHAR(50),
    ResourceGroup NVARCHAR(100),
    ServiceFamily NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE ResourceLocation IS NOT NULL
GROUP BY ResourceLocation
ORDER BY TotalCostUSD DESC;

-- ========================================================
-- QUERY 7: Monthly Cost Trend
-- ========================================================
SELECT 
    YEAR(TRY_CAST(Date AS DATE)) as Year,
    MONTH(TRY_CAST(Date AS DATE)) as Month,
    COUNT(*) as TransactionCount,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as MonthlyCostUSD,
    AVG(TRY_CAST(CostInUSD as DECIMAL(18,2))) as AvgTransactionCost
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    Date NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE Date IS NOT NULL
GROUP BY YEAR(TRY_CAST(Date AS DATE)), MONTH(TRY_CAST(Date AS DATE))
ORDER BY Year DESC, Month DESC;

-- ========================================================
-- QUERY 8: Charge Type Analysis
-- ========================================================
SELECT 
    ChargeType,
    COUNT(*) as TransactionCount,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as TotalCostUSD,
    AVG(TRY_CAST(CostInUSD as DECIMAL(18,2))) as AvgCostPerTransaction
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    ChargeType NVARCHAR(50),
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE ChargeType IS NOT NULL
GROUP BY ChargeType
ORDER BY TotalCostUSD DESC;

-- ========================================================
-- QUERY 9: Recent Activity (Last 7 Days)
-- ========================================================
SELECT 
    Date,
    ServiceFamily,
    ResourceGroup,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as DailyCost
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    Date NVARCHAR(100),
    ServiceFamily NVARCHAR(100),
    ResourceGroup NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE TRY_CAST(Date AS DATE) >= DATEADD(day, -7, GETDATE())
GROUP BY Date, ServiceFamily, ResourceGroup
ORDER BY Date DESC, DailyCost DESC;

-- ========================================================
-- QUERY 10: Zero Cost Items (Free Tier Usage)
-- ========================================================
SELECT 
    ServiceFamily,
    MeterCategory,
    ResourceGroup,
    COUNT(*) as FreeTransactions
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    ServiceFamily NVARCHAR(100),
    MeterCategory NVARCHAR(100),
    ResourceGroup NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE TRY_CAST(CostInUSD as DECIMAL(18,2)) = 0 OR CostInUSD = '0'
GROUP BY ServiceFamily, MeterCategory, ResourceGroup
ORDER BY FreeTransactions DESC;