-- ============================================
-- WORKING SYNAPSE QUERY FOR YOUR BILLING DATA
-- ============================================
-- Storage Account: billingstorage77626
-- Container: billing-exports
-- Workspace: wiv-synapse-billing
-- ============================================
-- IMPORTANT: Run this in Synapse Studio
-- Connect to: Built-in (serverless SQL pool)
-- ============================================

-- 1. Test query - Check if files exist
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
) 
WITH (
    Date NVARCHAR(100),
    ServiceFamily NVARCHAR(100),
    MeterCategory NVARCHAR(100),
    ResourceGroup NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData;

-- 2. If wildcard doesn't work, try specific file names
-- List the actual files in your storage and use them here
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/20250801-20250831/DailyBillingExport_*.csv',
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
) AS BillingData;

-- 3. Daily cost summary
SELECT 
    CAST(Date AS DATE) as BillingDate,
    SUM(TRY_CAST(CostInUSD AS FLOAT)) as TotalCostUSD,
    COUNT(*) as TransactionCount
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
) 
WITH (
    Date NVARCHAR(100),
    ServiceFamily NVARCHAR(100),
    MeterCategory NVARCHAR(100),
    ResourceGroup NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
GROUP BY CAST(Date AS DATE)
ORDER BY BillingDate DESC;