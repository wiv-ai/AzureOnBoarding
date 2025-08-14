-- Test query to check Synapse access to billing data
SELECT TOP 10 
    Date,
    ServiceFamily,
    ResourceGroup,
    CostInUSD,
    SubscriptionName
FROM OPENROWSET(
    BULK 'https://billingstorage73919.blob.core.windows.net/billing-exports/billing-data/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
ORDER BY Date DESC
