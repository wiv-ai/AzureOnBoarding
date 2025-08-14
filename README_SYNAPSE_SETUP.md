# Azure Synapse Billing Analytics Setup

## Overview
This solution provides a complete setup for analyzing Azure billing data using Azure Synapse Analytics with external tables and remote query capabilities.

## Components

### 1. SQL Setup Script (`synapse_external_table_setup.sql`)
Creates external tables in Synapse to query billing data directly from Azure Blob Storage.

**Features:**
- External table over CSV billing exports
- Uses HADOOP data source type for compatibility
- Includes SAS token authentication
- Sample analytical queries included

### 2. Python Remote Query Client (`synapse_remote_query_client.py`)
Python client for executing queries remotely against Synapse.

**Features:**
- Service principal authentication
- ODBC connection for reliable query execution
- Pre-built methods for common billing analytics
- Returns results as Pandas DataFrames

## Setup Instructions

### Step 1: Run the Synapse Setup Script

1. Open [Synapse Studio](https://web.azuresynapse.net)
2. Select workspace: `wiv-synapse-billing`
3. Connect to: **Built-in** serverless SQL pool
4. Open `synapse_external_table_setup.sql`
5. Run the script step by step (each GO statement)

This will create:
- Database: `BillingAnalytics`
- Credential: `BillingStorageCredential` (with SAS token)
- Data Source: `BillingDataSource`
- External Table: `BillingData`

### Step 2: Install Python Dependencies

```bash
pip install azure-identity pandas pyodbc
```

For Linux/Mac, you may also need:
```bash
# Ubuntu/Debian
sudo apt-get install unixodbc-dev

# Mac
brew install unixodbc
```

### Step 3: Configure and Run Python Client

```python
from synapse_remote_query_client import SynapseAPIClient

# Initialize client
client = SynapseAPIClient(
    tenant_id='ba153ff0-3397-4ef5-a214-dd33e8c37bff',
    client_id='554b11c1-18f9-46b5-a096-30e0a2cfae6f',
    client_secret='tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams',
    workspace_name='wiv-synapse-billing',
    database_name='BillingAnalytics'
)

# Get daily costs
daily_costs = client.get_daily_costs(days_back=30)
print(daily_costs)

# Get billing summary
summary = client.query_billing_summary(
    start_date='2025-08-01',
    end_date='2025-08-31'
)
print(summary)
```

## Available Query Methods

| Method | Description | Parameters |
|--------|-------------|------------|
| `query_billing_summary()` | Get cost summary by resource group and service | `start_date`, `end_date` |
| `get_daily_costs()` | Get daily cost trend | `days_back` |
| `get_top_resources()` | Get most expensive resources | `limit` |
| `get_cost_by_location()` | Cost breakdown by Azure region | None |
| `get_monthly_trend()` | Monthly cost trend | None |
| `execute_query_odbc()` | Execute custom SQL query | `query` |

## Connection Details

### Synapse Workspace
- **Workspace**: wiv-synapse-billing
- **SQL Endpoint**: wiv-synapse-billing-ondemand.sql.azuresynapse.net
- **Database**: BillingAnalytics
- **Pool Type**: Built-in (serverless)

### Storage Account
- **Account**: billingstorage77626
- **Container**: billing-exports
- **Path Pattern**: `/billing-data/DailyBillingExport/*/*.csv`

### Authentication
- **Type**: Service Principal
- **App ID**: 554b11c1-18f9-46b5-a096-30e0a2cfae6f
- **Tenant**: ba153ff0-3397-4ef5-a214-dd33e8c37bff

## Troubleshooting

### Issue: "File cannot be opened"
**Solution**: Ensure you're using the Built-in serverless SQL pool, not a dedicated pool.

### Issue: "Invalid object name 'BillingData'"
**Solution**: Run the setup script first to create the external table.

### Issue: ODBC Driver not found
**Solution**: Install Microsoft ODBC Driver 18 for SQL Server:
```bash
# Windows: Download from Microsoft
# Linux: 
curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list > /etc/apt/sources.list.d/mssql-release.list
apt-get update
ACCEPT_EULA=Y apt-get install -y msodbcsql18
```

### Issue: Authentication failed
**Solution**: Verify service principal credentials and ensure it has:
- Synapse Administrator role on workspace
- Storage Blob Data Reader on storage account

## SAS Token Renewal

The SAS token in the credential expires after 30 days. To renew:

1. Generate new SAS token:
```bash
az storage container generate-sas \
    --account-name billingstorage77626 \
    --name billing-exports \
    --permissions rl \
    --expiry $(date -u -d '30 days' '+%Y-%m-%dT%H:%MZ') \
    --output tsv
```

2. Update credential in Synapse:
```sql
ALTER DATABASE SCOPED CREDENTIAL BillingStorageCredential
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
SECRET = '<new-sas-token>';
```

## Sample Queries

### Total Cost by Day
```sql
SELECT 
    CAST(date AS DATE) as BillingDate,
    SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as TotalCost
FROM BillingData
GROUP BY CAST(date AS DATE)
ORDER BY BillingDate DESC;
```

### Top 5 Most Expensive Services
```sql
SELECT TOP 5
    serviceFamily,
    SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as TotalCost
FROM BillingData
GROUP BY serviceFamily
ORDER BY TotalCost DESC;
```

### Cost by Resource Group
```sql
SELECT 
    resourceGroupName,
    SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as TotalCost
FROM BillingData
WHERE resourceGroupName IS NOT NULL
GROUP BY resourceGroupName
ORDER BY TotalCost DESC;
```

## Notes

- The external table automatically picks up new CSV files as they're added
- Billing exports are cumulative (each file contains month-to-date data)
- Query performance depends on file size and Synapse serverless pool capacity
- Consider creating views for commonly used queries