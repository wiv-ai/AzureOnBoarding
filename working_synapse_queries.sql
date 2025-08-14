-- ========================================================
-- WORKING AZURE SYNAPSE QUERIES FOR BILLING DATA
-- ========================================================
-- Use these queries in Synapse Studio with Built-in serverless SQL pool
-- These queries use the EXACT file path to avoid wildcard listing issues

-- ========================================================
-- EXACT FILE PATH QUERIES (THESE WORK!)
-- ========================================================

-- 1. Query your specific billing file (VERIFIED WORKING)
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
) AS BillingData;

-- 2. Daily Cost Summary (using exact file)
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

-- 3. Service Cost Breakdown (using exact file)
SELECT 
    ServiceFamily,
    MeterCategory,
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
    MeterCategory NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE ServiceFamily IS NOT NULL
GROUP BY ServiceFamily, MeterCategory
ORDER BY TotalCostUSD DESC;

-- 4. Resource Group Analysis (using exact file)
SELECT 
    ResourceGroup,
    COUNT(*) as TransactionCount,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as TotalCostUSD
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    ResourceGroup NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE ResourceGroup IS NOT NULL AND ResourceGroup != ''
GROUP BY ResourceGroup
ORDER BY TotalCostUSD DESC;

-- 5. Top 10 Most Expensive Resources (using exact file)
SELECT TOP 10
    ResourceId,
    ServiceFamily,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as TotalCostUSD
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    ResourceId NVARCHAR(500),
    ServiceFamily NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE ResourceId IS NOT NULL AND ResourceId != ''
GROUP BY ResourceId, ServiceFamily
ORDER BY TotalCostUSD DESC;

-- ========================================================
-- CREATE A VIEW FOR EASIER ACCESS (RUN ONCE)
-- ========================================================
-- This simplifies your queries significantly

CREATE OR ALTER VIEW CurrentBillingData AS
SELECT *
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
) AS BillingData;

-- ========================================================
-- AFTER CREATING THE VIEW, USE THESE SIMPLE QUERIES
-- ========================================================

-- Simple query using the view
SELECT TOP 100 * FROM CurrentBillingData ORDER BY Date DESC;

-- Daily costs using the view
SELECT 
    CAST(Date AS DATE) as BillingDate,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as DailyCost
FROM CurrentBillingData
GROUP BY CAST(Date AS DATE)
ORDER BY BillingDate DESC;

-- Service costs using the view
SELECT 
    ServiceFamily,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as TotalCost
FROM CurrentBillingData
GROUP BY ServiceFamily
ORDER BY TotalCost DESC;

-- ========================================================
-- STORED PROCEDURE TO UPDATE FILE PATH (FOR AUTOMATION)
-- ========================================================
-- When new export files are created, update this procedure

CREATE OR ALTER PROCEDURE UpdateBillingFilePath
    @NewFilePath NVARCHAR(500)
AS
BEGIN
    -- Drop and recreate the view with new file path
    DECLARE @SQL NVARCHAR(MAX)
    SET @SQL = '
    CREATE OR ALTER VIEW CurrentBillingData AS
    SELECT *
    FROM OPENROWSET(
        BULK ''' + @NewFilePath + ''',
        FORMAT = ''CSV'',
        PARSER_VERSION = ''2.0'',
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
    ) AS BillingData'
    
    EXEC sp_executesql @SQL
END;

-- Example: Update to a new file
-- EXEC UpdateBillingFilePath 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250901-20250930/DailyBillingExport_newguid.csv';