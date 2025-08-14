-- Validated Query for Remote Execution
-- Use this in Synapse Studio or SQL client tools

-- Connection Details:
-- Server: wiv-synapse-billing-ondemand.sql.azuresynapse.net
-- Database: master
-- Authentication: Azure Active Directory - Service Principal
-- Username: 554b11c1-18f9-46b5-a096-30e0a2cfae6f
-- Password: tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams

-- Query 1: Test basic connectivity
SELECT 'Connected to Synapse' as Status, GETDATE() as Timestamp;

-- Query 2: Read billing data with exact file path
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

-- Query 3: Aggregated billing summary
SELECT 
    ServiceFamily,
    ResourceGroup,
    COUNT(*) as RecordCount,
    SUM(TRY_CAST(CostInUSD as FLOAT)) as TotalCost
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    ServiceFamily NVARCHAR(100),
    ResourceGroup NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
GROUP BY ServiceFamily, ResourceGroup
ORDER BY TotalCost DESC;
