-- ============================================
-- SYNAPSE QUERIES WITH EXPLICIT SCHEMA
-- ============================================
-- Fixes: "Schema cannot be determined from data files"
-- ============================================

-- 1. Query with explicit schema definition
SELECT * 
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) 
WITH (
    Date DATETIME2,
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
    Quantity FLOAT,
    CostInBillingCurrency FLOAT,
    CostInUSD FLOAT,
    PayGPrice FLOAT,
    BillingCurrencyCode NVARCHAR(10),
    SubscriptionName NVARCHAR(100),
    SubscriptionId NVARCHAR(50),
    ProductName NVARCHAR(200),
    Frequency NVARCHAR(50),
    UnitOfMeasure NVARCHAR(50),
    Tags NVARCHAR(MAX)
) AS BillingData;

-- 2. Simple query - Top 10 records with key columns only
SELECT TOP 10 * 
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
) 
WITH (
    Date VARCHAR(50),
    ServiceFamily VARCHAR(100),
    MeterCategory VARCHAR(100),
    ResourceGroup VARCHAR(100),
    CostInUSD VARCHAR(50)
) AS BillingData;

-- 3. Alternative: Try with FIELDTERMINATOR and ROWTERMINATOR
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2
) 
WITH (
    Column1 NVARCHAR(100),
    Column2 NVARCHAR(100),
    Column3 NVARCHAR(100),
    Column4 NVARCHAR(100),
    Column5 NVARCHAR(100),
    Column6 NVARCHAR(100),
    Column7 NVARCHAR(100),
    Column8 NVARCHAR(100),
    Column9 NVARCHAR(100),
    Column10 NVARCHAR(100)
) AS BillingData;

-- 4. Check first few rows to see actual structure
SELECT TOP 5 *
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    FIRSTROW = 1
) 
WITH (
    FullRow NVARCHAR(MAX)
) AS BillingData;

-- 5. Daily cost summary with explicit schema
SELECT 
    CAST(Date AS DATE) as BillingDate,
    SUM(CAST(CostInUSD AS FLOAT)) as TotalCostUSD,
    COUNT(*) as RecordCount
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
) 
WITH (
    Date DATETIME2,
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
    Quantity FLOAT,
    CostInBillingCurrency FLOAT,
    CostInUSD FLOAT,
    PayGPrice FLOAT,
    BillingCurrencyCode NVARCHAR(10),
    SubscriptionName NVARCHAR(100),
    SubscriptionId NVARCHAR(50),
    ProductName NVARCHAR(200),
    Frequency NVARCHAR(50),
    UnitOfMeasure NVARCHAR(50),
    Tags NVARCHAR(MAX)
) AS BillingData
GROUP BY CAST(Date AS DATE)
ORDER BY BillingDate DESC;