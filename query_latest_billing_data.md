# How to Query the Most Updated Billing Data in Synapse

## Understanding the Data Structure

### The Duplication Problem
Azure Cost Management exports create **cumulative month-to-date** files daily:
- **Day 1 file**: Contains only Day 1 costs
- **Day 2 file**: Contains Day 1 + Day 2 costs (cumulative)
- **Day 3 file**: Contains Day 1 + Day 2 + Day 3 costs (cumulative)
- **Day 30 file**: Contains the entire month's data

**⚠️ IMPORTANT**: If you query ALL files, you'll get massive duplication. For example, Day 1's costs would appear 30 times in a month!

## Solution: Query Only the Latest File

### Method 1: Using the BillingData View (Simplified but May Duplicate)

The basic view queries ALL files, which causes duplication:
```sql
-- ❌ DON'T USE THIS - Will cause duplication
SELECT * FROM BillingAnalytics.dbo.BillingData
```

### Method 2: Direct Query with Latest File Filter (Recommended)

Since the view doesn't filter for the latest file, you need to query the storage directly:

```sql
-- ✅ RECOMMENDED: Get only the latest export file
WITH LatestExport AS (
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'https://<storage_account>.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        HEADER_ROW = TRUE
    ) AS files
)
SELECT * 
FROM OPENROWSET(
    BULK 'https://<storage_account>.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingData
WHERE filepath(1) = (SELECT LatestPath FROM LatestExport)
```

### Method 3: Create an Improved View (One-Time Setup)

Create a better view that automatically gets only the latest data:

```sql
-- Drop existing view if needed
DROP VIEW IF EXISTS BillingDataLatest;
GO

-- Create view that always returns latest export only
CREATE VIEW BillingDataLatest AS
WITH LatestExport AS (
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'abfss://billing-exports@<storage_account>.dfs.core.windows.net/billing-data/DailyBillingExport/*/*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        FIRSTROW = 2
    ) AS files
)
SELECT * 
FROM OPENROWSET(
    BULK 'abfss://billing-exports@<storage_account>.dfs.core.windows.net/billing-data/DailyBillingExport/*/*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
) 
WITH (
    date NVARCHAR(100),
    serviceFamily NVARCHAR(200),
    meterCategory NVARCHAR(200),
    meterSubCategory NVARCHAR(200),
    meterName NVARCHAR(500),
    billingAccountName NVARCHAR(200),
    costCenter NVARCHAR(100),
    resourceGroupName NVARCHAR(200),
    resourceLocation NVARCHAR(100),
    consumedService NVARCHAR(200),
    ResourceId NVARCHAR(1000),
    chargeType NVARCHAR(100),
    publisherType NVARCHAR(100),
    quantity NVARCHAR(100),
    costInBillingCurrency NVARCHAR(100),
    costInUsd NVARCHAR(100),
    PayGPrice NVARCHAR(100),
    billingCurrency NVARCHAR(10),
    subscriptionName NVARCHAR(200),
    SubscriptionId NVARCHAR(100),
    ProductName NVARCHAR(500),
    frequency NVARCHAR(100),
    unitOfMeasure NVARCHAR(100),
    tags NVARCHAR(4000)
) AS BillingData
WHERE filepath(1) = (SELECT LatestPath FROM LatestExport);
GO

-- Now you can simply query:
SELECT * FROM BillingAnalytics.dbo.BillingDataLatest
```

## Common Query Patterns for Latest Data

### 1. Get Current Month's Daily Costs
```sql
-- Daily costs for current month (no duplication)
WITH LatestExport AS (
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'https://<storage_account>.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS files
)
SELECT 
    CAST(Date AS DATE) as BillingDate,
    SUM(CAST(CostInUSD AS FLOAT)) as DailyCost,
    COUNT(DISTINCT ResourceId) as ResourceCount
FROM OPENROWSET(
    BULK 'https://<storage_account>.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
WHERE filepath(1) = (SELECT LatestPath FROM LatestExport)
  AND MONTH(CAST(Date AS DATE)) = MONTH(GETDATE())
  AND YEAR(CAST(Date AS DATE)) = YEAR(GETDATE())
GROUP BY CAST(Date AS DATE)
ORDER BY BillingDate DESC
```

### 2. Get Last 7 Days Summary
```sql
WITH LatestExport AS (
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'https://<storage_account>.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS files
)
SELECT 
    ServiceFamily,
    ResourceGroupName,
    SUM(CAST(CostInUSD AS FLOAT)) as TotalCost,
    COUNT(*) as TransactionCount
FROM OPENROWSET(
    BULK 'https://<storage_account>.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
WHERE filepath(1) = (SELECT LatestPath FROM LatestExport)
  AND CAST(Date AS DATE) >= DATEADD(day, -7, GETDATE())
GROUP BY ServiceFamily, ResourceGroupName
ORDER BY TotalCost DESC
```

### 3. Get Specific Date Range
```sql
WITH LatestExport AS (
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'https://<storage_account>.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS files
)
SELECT *
FROM OPENROWSET(
    BULK 'https://<storage_account>.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
WHERE filepath(1) = (SELECT LatestPath FROM LatestExport)
  AND CAST(Date AS DATE) BETWEEN '2024-12-01' AND '2024-12-15'
```

## Using with Python Remote Client

When using the `synapse_remote_query_client.py`, you can execute these queries:

```python
from synapse_remote_query_client import SynapseAPIClient

# Initialize client
client = SynapseAPIClient(
    tenant_id='your_tenant_id',
    client_id='your_client_id', 
    client_secret='your_secret',
    workspace_name='wiv-synapse-billing',
    database_name='BillingAnalytics'
)

# Query latest data without duplication
query = """
WITH LatestExport AS (
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'https://your_storage.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS files
)
SELECT 
    CAST(Date AS DATE) as BillingDate,
    ServiceFamily,
    SUM(CAST(CostInUSD AS FLOAT)) as TotalCost
FROM OPENROWSET(
    BULK 'https://your_storage.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
WHERE filepath(1) = (SELECT LatestPath FROM LatestExport)
  AND CAST(Date AS DATE) >= DATEADD(day, -30, GETDATE())
GROUP BY CAST(Date AS DATE), ServiceFamily
ORDER BY BillingDate DESC, TotalCost DESC
"""

# Execute query
df = client.execute_query_odbc(query)
print(df)
```

## Key Points to Remember

1. **Always filter for the latest file** to avoid duplication
2. **The latest file contains all month-to-date data** - you don't need older files
3. **Use `filepath(1)` function** to identify and filter files
4. **Cast date columns** properly: `CAST(Date AS DATE)`
5. **Cast numeric columns** for calculations: `CAST(CostInUSD AS FLOAT)`

## Performance Tips

1. **Filter early**: Apply date filters in the WHERE clause to reduce data scanned
2. **Use aggregations**: GROUP BY reduces the result set size
3. **Limit columns**: Select only needed columns instead of `SELECT *`
4. **Consider caching**: For dashboards, consider caching results for a few hours

## Troubleshooting

If queries return duplicated data:
- ✅ Check you're using the `LatestExport` CTE pattern
- ✅ Verify the filepath filter is applied
- ✅ Ensure you're not querying the basic `BillingData` view

If queries return no data:
- ✅ Check if billing export has run (takes 5-30 minutes after setup)
- ✅ Verify storage path is correct
- ✅ Ensure service principal has Storage Blob Data Reader permission
- ✅ Check date filters aren't excluding all data