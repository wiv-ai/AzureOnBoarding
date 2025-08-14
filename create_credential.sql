-- ========================================================
-- CREATE CREDENTIAL FOR STORAGE ACCESS
-- ========================================================
-- Run this in Synapse Studio FIRST, then try the queries

-- Option 1: Use Managed Identity (Recommended)
CREATE DATABASE SCOPED CREDENTIAL WorkspaceIdentity
WITH IDENTITY = 'Managed Identity';

-- Option 2: Use SAS Token
CREATE DATABASE SCOPED CREDENTIAL SASCredential
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
SECRET = 'se=2025-09-13T14%3A10Z&sp=rl&sv=2022-11-02&sr=c&sig=UgnaupGU791CqSr4B86GdFKWrSTXjX%2BYh6VW/F%2BXBfE%3D';

-- Create External Data Source using the credential
CREATE EXTERNAL DATA SOURCE BillingStorageWithCredential
WITH (
    TYPE = BLOB_STORAGE,
    LOCATION = 'https://billingstorage77626.blob.core.windows.net/billing-exports',
    CREDENTIAL = WorkspaceIdentity  -- or SASCredential
);

-- Now query using the external data source
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
    DATA_SOURCE = 'BillingStorageWithCredential',
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
