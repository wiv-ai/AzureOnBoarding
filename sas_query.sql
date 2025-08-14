-- Query using SAS token (for testing if permissions are the issue)
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv?se=2025-08-21T14%3A07Z&sp=rl&sv=2022-11-02&sr=c&sig=RyYC84egGMEOcqgXUrK%2Bja%2B4ZKu%2B71zzmhtyotiWnkI%3D',
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
