-- Query billing data from actual file location
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
