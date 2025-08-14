-- ========================================================
-- SYNAPSE QUERY FOR LATEST BILLING FILE
-- ========================================================
-- Generated on: Thu Aug 14 01:59:20 PM UTC 2025
-- Latest file: DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv
-- Date range: 20250801-20250831
-- ========================================================

-- Query the latest billing data
SELECT TOP 100 *
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
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

-- Daily cost summary
SELECT 
    CAST(Date AS DATE) as BillingDate,
    COUNT(*) as TransactionCount,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as DailyCostUSD
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    Date NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE Date IS NOT NULL
GROUP BY CAST(Date AS DATE)
ORDER BY BillingDate DESC;

-- Service cost breakdown
SELECT 
    ServiceFamily,
    COUNT(*) as TransactionCount,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as TotalCostUSD
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    ServiceFamily NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE ServiceFamily IS NOT NULL
GROUP BY ServiceFamily
ORDER BY TotalCostUSD DESC;
