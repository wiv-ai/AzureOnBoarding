-- IMPORTANT: Use these queries in Synapse Studio
-- Connect to: Built-in (serverless SQL pool)

-- ============================================
-- WILDCARD QUERIES (Recommended for Production)
-- ============================================

-- Query 1: Get latest billing data using wildcards
-- This will automatically pick up new daily exports
SELECT TOP 100 *
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

-- Query 2: Get billing summary by service (all files)
SELECT 
    ServiceFamily,
    ResourceGroup,
    COUNT(*) as RecordCount,
    SUM(TRY_CAST(CostInUSD as FLOAT)) as TotalCost,
    MIN(Date) as FirstDate,
    MAX(Date) as LastDate
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
GROUP BY ServiceFamily, ResourceGroup
ORDER BY TotalCost DESC;

-- Query 3: Daily cost trend (using wildcards)
SELECT 
    Date,
    COUNT(*) as TransactionCount,
    SUM(TRY_CAST(CostInUSD as FLOAT)) as DailyCost
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
GROUP BY Date
ORDER BY Date DESC;

-- Query 4: Top 10 most expensive resources (all time)
SELECT TOP 10
    ResourceId,
    ResourceGroup,
    ServiceFamily,
    SUM(TRY_CAST(CostInUSD as FLOAT)) as TotalCost
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
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE ResourceId IS NOT NULL
GROUP BY ResourceId, ResourceGroup, ServiceFamily
ORDER BY TotalCost DESC;

-- ============================================
-- SPECIFIC FILE QUERY (for testing)
-- ============================================

-- Query 5: Specific file (if you need to query a particular export)
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    Date NVARCHAR(100),
    ServiceFamily NVARCHAR(100),
    ResourceGroup NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData;
