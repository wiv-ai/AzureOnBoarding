-- ========================================================
-- SETUP EXTERNAL TABLE IN SYNAPSE
-- ========================================================
-- Run these commands in order in Synapse Studio
-- Make sure you're connected to Built-in serverless SQL pool

-- Step 1: Create a new database (if needed)
CREATE DATABASE IF NOT EXISTS BillingAnalytics;
GO

USE BillingAnalytics;
GO

-- Step 2: Create master key (required for credentials)
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongPassword123!@#';
GO

-- Step 3: Create database scoped credential with SAS token
-- Remove the ? from the beginning of the SAS token
CREATE DATABASE SCOPED CREDENTIAL BillingSAS
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
SECRET = 'sv=2022-11-02&sr=b&sp=r&se=2025-08-21T14%3A17Z&sig=J%2FnAgPUSHaOCGKwfiqTij3wLleNOEnepjEto2YFoMvc%3D';
GO

-- Step 4: Create external data source
CREATE EXTERNAL DATA SOURCE BillingDataSource
WITH (
    TYPE = BLOB_STORAGE,
    LOCATION = 'https://billingstorage77626.blob.core.windows.net',
    CREDENTIAL = BillingSAS
);
GO

-- Step 5: Create external file format
CREATE EXTERNAL FILE FORMAT CSVFormat
WITH (
    FORMAT_TYPE = DELIMITEDTEXT,
    FORMAT_OPTIONS (
        FIELD_TERMINATOR = ',',
        STRING_DELIMITER = '"',
        FIRST_ROW = 2,
        USE_TYPE_DEFAULT = TRUE
    )
);
GO

-- Step 6: Now query using the external data source
SELECT TOP 100 *
FROM OPENROWSET(
    BULK 'billing-exports/billing.csv',
    DATA_SOURCE = 'BillingDataSource',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    date NVARCHAR(100),
    serviceFamily NVARCHAR(100),
    meterCategory NVARCHAR(100),
    resourceGroupName NVARCHAR(100),
    costInUsd NVARCHAR(50)
) AS BillingData;

-- ========================================================
-- ALTERNATIVE: Try with Managed Identity
-- ========================================================
-- If SAS doesn't work, try managed identity

-- Drop the SAS credential if it exists
DROP DATABASE SCOPED CREDENTIAL IF EXISTS BillingSAS;
GO

-- Create credential using Managed Identity
CREATE DATABASE SCOPED CREDENTIAL ManagedIdentityCredential
WITH IDENTITY = 'Managed Identity';
GO

-- Create external data source with Managed Identity
CREATE EXTERNAL DATA SOURCE BillingDataSourceMI
WITH (
    TYPE = BLOB_STORAGE,
    LOCATION = 'https://billingstorage77626.blob.core.windows.net',
    CREDENTIAL = ManagedIdentityCredential
);
GO

-- Query using Managed Identity
SELECT TOP 100 *
FROM OPENROWSET(
    BULK 'billing-exports/billing.csv',
    DATA_SOURCE = 'BillingDataSourceMI',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    date NVARCHAR(100),
    serviceFamily NVARCHAR(100),
    meterCategory NVARCHAR(100),
    resourceGroupName NVARCHAR(100),
    costInUsd NVARCHAR(50)
) AS BillingData;

-- ========================================================
-- ALTERNATIVE: Direct query without SAS in URL
-- ========================================================
-- Try the simplified path without SAS token

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
    resourceGroupName NVARCHAR(100),
    costInUsd NVARCHAR(50)
) AS BillingData;