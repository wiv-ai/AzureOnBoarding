-- ============================================
-- FIXED SYNAPSE QUERIES WITH UTF8 COLLATION
-- ============================================

-- 1. Query specific file with UTF8 collation
SELECT TOP 10 * 
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport_b25100c0-b66f-4391-ae32-2661f9e8e729.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
) 
WITH (
    Date NVARCHAR(100) COLLATE Latin1_General_100_CI_AS_SC_UTF8,
    ServiceFamily NVARCHAR(100) COLLATE Latin1_General_100_CI_AS_SC_UTF8,
    MeterCategory NVARCHAR(100) COLLATE Latin1_General_100_CI_AS_SC_UTF8,
    ResourceGroup NVARCHAR(100) COLLATE Latin1_General_100_CI_AS_SC_UTF8,
    CostInUSD NVARCHAR(50) COLLATE Latin1_General_100_CI_AS_SC_UTF8
) AS BillingData;

-- 2. Query both files explicitly (not using wildcard)
SELECT * 
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport_b25100c0-b66f-4391-ae32-2661f9e8e729.csv',
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

UNION ALL

SELECT * 
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport_d6a0aeec-2a67-4a71-a9e4-4a6258720414.csv',
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
) AS BillingData2;

-- 3. Simplest possible query - just read raw data
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport_b25100c0-b66f-4391-ae32-2661f9e8e729.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0'
) AS BillingData;

-- 4. Alternative using SAS token (if public access is blocked)
-- First, generate a SAS token in Azure Portal for the storage account
-- Then use this query format:
/*
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport_b25100c0-b66f-4391-ae32-2661f9e8e729.csv?[SAS_TOKEN_HERE]',
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
*/

-- 5. Test with minimal columns
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/DailyBillingExport_b25100c0-b66f-4391-ae32-2661f9e8e729.csv',
    FORMAT = 'CSV',
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2
) 
WITH (
    Col1 NVARCHAR(100),
    Col2 NVARCHAR(100),
    Col3 NVARCHAR(100),
    Col4 NVARCHAR(100),
    Col5 NVARCHAR(100)
) AS BillingData;