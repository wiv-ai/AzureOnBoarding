-- ========================================================
-- WORKING SYNAPSE QUERY - VERIFIED
-- ========================================================
-- IMPORTANT: The CSV has LOWERCASE column names!

-- Option 1: Query from SIMPLE PATH (billing.csv)
SELECT TOP 100 *
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    date NVARCHAR(100),
    serviceFamily NVARCHAR(100),
    meterCategory NVARCHAR(100),
    meterSubCategory NVARCHAR(100),
    meterName NVARCHAR(200),
    billingAccountName NVARCHAR(100),
    costCenter NVARCHAR(50),
    resourceGroupName NVARCHAR(100),
    resourceLocation NVARCHAR(50),
    consumedService NVARCHAR(100),
    ResourceId NVARCHAR(500),
    chargeType NVARCHAR(50),
    publisherType NVARCHAR(50),
    quantity NVARCHAR(50),
    costInBillingCurrency NVARCHAR(50),
    costInUsd NVARCHAR(50),
    PayGPrice NVARCHAR(50),
    billingCurrency NVARCHAR(10),
    subscriptionName NVARCHAR(100),
    SubscriptionId NVARCHAR(50),
    ProductName NVARCHAR(200),
    frequency NVARCHAR(50),
    unitOfMeasure NVARCHAR(50),
    tags NVARCHAR(MAX)
) AS BillingData;

-- Option 2: Query from ORIGINAL PATH with correct column names
SELECT TOP 100 *
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    date NVARCHAR(100),
    serviceFamily NVARCHAR(100),
    meterCategory NVARCHAR(100),
    meterSubCategory NVARCHAR(100),
    meterName NVARCHAR(200),
    billingAccountName NVARCHAR(100),
    costCenter NVARCHAR(50),
    resourceGroupName NVARCHAR(100),
    resourceLocation NVARCHAR(50),
    consumedService NVARCHAR(100),
    ResourceId NVARCHAR(500),
    chargeType NVARCHAR(50),
    publisherType NVARCHAR(50),
    quantity NVARCHAR(50),
    costInBillingCurrency NVARCHAR(50),
    costInUsd NVARCHAR(50),
    PayGPrice NVARCHAR(50),
    billingCurrency NVARCHAR(10),
    subscriptionName NVARCHAR(100),
    SubscriptionId NVARCHAR(50),
    ProductName NVARCHAR(200),
    frequency NVARCHAR(50),
    unitOfMeasure NVARCHAR(50),
    tags NVARCHAR(MAX)
) AS BillingData;

-- Option 3: Simplified query with just key columns
SELECT TOP 100 *
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    date NVARCHAR(100),
    serviceFamily NVARCHAR(100),
    resourceGroupName NVARCHAR(100),
    costInUsd NVARCHAR(50)
) AS BillingData;

-- Option 4: Daily cost summary
SELECT 
    CAST(date AS DATE) as BillingDate,
    SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as DailyCostUSD,
    COUNT(*) as TransactionCount
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    date NVARCHAR(100),
    costInUsd NVARCHAR(50)
) AS BillingData
GROUP BY CAST(date AS DATE)
ORDER BY BillingDate DESC;

-- Option 5: Cost by service
SELECT 
    serviceFamily,
    SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as TotalCostUSD,
    COUNT(*) as TransactionCount
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    serviceFamily NVARCHAR(100),
    costInUsd NVARCHAR(50)
) AS BillingData
GROUP BY serviceFamily
ORDER BY TotalCostUSD DESC;