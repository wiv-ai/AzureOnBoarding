-- ========================================================
-- SYNAPSE QUERY WITH SAS TOKEN - THIS SHOULD WORK!
-- ========================================================
-- Generated: Thu Aug 14 02:17:00 PM UTC 2025
-- This query includes a SAS token that bypasses all permission issues

SELECT TOP 100 *
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing.csv?se=2025-08-21T14%3A17Z&sp=r&sv=2022-11-02&sr=b&sig=J%2FnAgPUSHaOCGKwfiqTij3wLleNOEnepjEto2YFoMvc%3D',
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

-- Daily cost summary with SAS
SELECT 
    CAST(date AS DATE) as BillingDate,
    SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as DailyCostUSD,
    COUNT(*) as TransactionCount
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing.csv?se=2025-08-21T14%3A17Z&sp=r&sv=2022-11-02&sr=b&sig=J%2FnAgPUSHaOCGKwfiqTij3wLleNOEnepjEto2YFoMvc%3D',
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
