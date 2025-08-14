-- ========================================================
-- AZURE SYNAPSE QUERIES FOR BILLING DATA - FIXED VERSION
-- ========================================================
-- IMPORTANT: Synapse serverless SQL pool has limitations with wildcard patterns
-- Solution: Use more specific patterns or exact paths

-- ========================================================
-- OPTION 1: SPECIFIC DATE RANGE (RECOMMENDED)
-- ========================================================
-- Use this pattern when you know the date range folder
-- This works because it's a specific path with wildcard only at the file level

-- Query current month's data (August 2025)
SELECT TOP 100 *
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport*.csv',
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
-- OPTION 2: EXACT FILE PATH (MOST RELIABLE)
-- ========================================================
-- Use when you need to query a specific export file

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
    ResourceGroup NVARCHAR(100),
    ResourceLocation NVARCHAR(50),
    CostInUSD NVARCHAR(50)
) AS BillingData;

-- ========================================================
-- OPTION 3: UNION MULTIPLE MONTHS (FOR CROSS-MONTH ANALYSIS)
-- ========================================================
-- Combine multiple specific date ranges using UNION ALL

-- Current and previous month combined
SELECT * FROM (
    -- August 2025
    SELECT 
        Date,
        ServiceFamily,
        ResourceGroup,
        TRY_CAST(CostInUSD as DECIMAL(18,2)) as CostUSD
    FROM OPENROWSET(
        BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        FIRSTROW = 2
    )
    WITH (
        Date NVARCHAR(100),
        ServiceFamily NVARCHAR(100),
        ResourceGroup NVARCHAR(100),
        CostInUSD NVARCHAR(50)
    ) AS Aug2025
    
    UNION ALL
    
    -- July 2025 (if exists)
    SELECT 
        Date,
        ServiceFamily,
        ResourceGroup,
        TRY_CAST(CostInUSD as DECIMAL(18,2)) as CostUSD
    FROM OPENROWSET(
        BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250701-20250731/DailyBillingExport*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        FIRSTROW = 2
    )
    WITH (
        Date NVARCHAR(100),
        ServiceFamily NVARCHAR(100),
        ResourceGroup NVARCHAR(100),
        CostInUSD NVARCHAR(50)
    ) AS Jul2025
) AS CombinedData
ORDER BY Date DESC;

-- ========================================================
-- DAILY COST SUMMARY (Single Month)
-- ========================================================
SELECT 
    CAST(Date AS DATE) as BillingDate,
    COUNT(*) as TransactionCount,
    COUNT(DISTINCT ResourceGroup) as UniqueResourceGroups,
    COUNT(DISTINCT ServiceFamily) as UniqueServices,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as DailyCostUSD
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport*.csv',
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
-- SERVICE COST BREAKDOWN (Current Month)
-- ========================================================
SELECT 
    ServiceFamily,
    MeterCategory,
    COUNT(*) as TransactionCount,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as TotalCostUSD,
    AVG(TRY_CAST(CostInUSD as DECIMAL(18,2))) as AvgCostPerTransaction
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport*.csv',
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

-- ========================================================
-- RESOURCE GROUP ANALYSIS (Current Month)
-- ========================================================
SELECT 
    ResourceGroup,
    COUNT(DISTINCT ServiceFamily) as ServicesUsed,
    COUNT(*) as TransactionCount,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as TotalCostUSD
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    ResourceGroup NVARCHAR(100),
    ServiceFamily NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE ResourceGroup IS NOT NULL AND ResourceGroup != ''
GROUP BY ResourceGroup
ORDER BY TotalCostUSD DESC;

-- ========================================================
-- TOP EXPENSIVE RESOURCES (Current Month)
-- ========================================================
SELECT TOP 20
    ResourceId,
    ResourceGroup,
    ServiceFamily,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as TotalCostUSD
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport*.csv',
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
WHERE ResourceId IS NOT NULL AND ResourceId != ''
GROUP BY ResourceId, ResourceGroup, ServiceFamily
ORDER BY TotalCostUSD DESC;

-- ========================================================
-- CREATING A VIEW FOR EASIER ACCESS (RUN ONCE)
-- ========================================================
-- Create a view to simplify queries
/*
CREATE VIEW BillingDataCurrentMonth AS
SELECT *
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport*.csv',
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

-- Then query the view simply:
SELECT TOP 100 * FROM BillingDataCurrentMonth ORDER BY Date DESC;
*/

-- ========================================================
-- DYNAMIC DATE RANGE QUERY
-- ========================================================
-- For programmatic access, build the path dynamically
-- Example: Generate current month's path
/*
DECLARE @CurrentYear INT = YEAR(GETDATE())
DECLARE @CurrentMonth INT = MONTH(GETDATE())
DECLARE @StartDate NVARCHAR(8) = CONCAT(@CurrentYear, RIGHT('0' + CAST(@CurrentMonth AS NVARCHAR(2)), 2), '01')
DECLARE @EndDate NVARCHAR(8) = CONCAT(@CurrentYear, RIGHT('0' + CAST(@CurrentMonth AS NVARCHAR(2)), 2), '31')
DECLARE @BulkPath NVARCHAR(500) = CONCAT('https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/', @StartDate, '-', @EndDate, '/DailyBillingExport*.csv')

-- Note: Dynamic BULK paths are not supported in OPENROWSET
-- You would need to use this path in your application code
*/