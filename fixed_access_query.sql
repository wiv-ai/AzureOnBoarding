-- ========================================================
-- FIXED ACCESS QUERIES FOR SYNAPSE
-- ========================================================
-- Use these after running fix_storage_access.sh

-- Option 1: Query with managed identity (recommended)
-- Make sure you're connected to Built-in serverless SQL pool
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
    ResourceGroup NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData;

-- Option 2: Create external data source (run once)
/*
CREATE EXTERNAL DATA SOURCE BillingStorage
WITH (
    TYPE = BLOB_STORAGE,
    LOCATION = 'https://billingstorage77626.blob.core.windows.net/billing-exports'
);

-- Then query using the data source
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
    DATA_SOURCE = 'BillingStorage',
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
