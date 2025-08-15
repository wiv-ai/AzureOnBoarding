# Azure Billing Analytics with Synapse

A comprehensive solution for automated Azure billing data export and analysis using Azure Synapse Analytics with **Managed Identity** authentication - no tokens, no expiration, no maintenance required!

## 🚀 Features

- **Automated Daily Billing Export** - Configures Azure Cost Management to export billing data daily
- **Azure Synapse Analytics Integration** - Serverless SQL pool for querying billing data
- **Managed Identity Authentication** - No SAS tokens or keys to manage, never expires
- **Service Principal Setup** - Automated creation and configuration of `wiv_account`
- **Comprehensive Permissions** - All required roles automatically assigned
- **Remote Query Support** - Python client for programmatic access
- **Single-Run Setup** - Enhanced retry logic ensures completion in one execution
- **Idempotent Design** - Safe to run multiple times

## 📋 Prerequisites

- Azure CLI installed and configured
- Active Azure subscription
- Bash shell environment
- Python 3.x (for remote queries)
- `pyodbc` and `pandas` (automatically installed by script)

## 🔧 Quick Start

1. **Clone the repository:**
```bash
git clone -b feature/billing-export-synapse https://github.com/wiv-ai/AzureOnBoarding.git
cd AzureOnBoarding
```

2. **Run the setup script:**
```bash
./startup_with_billing_synapse.sh
```

The script will:
- Check for existing `wiv_account` service principal (create if needed)
- Create resource group `wiv-rg` in `eastus2`
- Set up storage account for billing exports
- Configure daily billing export at midnight UTC
- Create Synapse workspace `wiv-synapse-billing`
- Set up Data Lake Storage Gen2
- Configure firewall rules (including your IP)
- Assign all necessary permissions
- Create `BillingAnalytics` database
- Set up `BillingData` view with Managed Identity
- Trigger first billing export immediately

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Azure Subscription                     │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌──────────────┐        ┌──────────────────────┐       │
│  │ Cost Mgmt    │───────▶│ Storage Account      │       │
│  │ Daily Export │        │ (billingstorage*)    │       │
│  └──────────────┘        └──────────────────────┘       │
│                                    │                      │
│                                    ▼                      │
│                          ┌──────────────────────┐        │
│                          │ Synapse Workspace    │        │
│                          │ (wiv-synapse-billing)│        │
│                          │                      │        │
│                          │ ┌──────────────────┐ │        │
│                          │ │ BillingAnalytics │ │        │
│                          │ │    Database      │ │        │
│                          │ └──────────────────┘ │        │
│                          │          │           │        │
│                          │          ▼           │        │
│                          │ ┌──────────────────┐ │        │
│                          │ │  BillingData     │ │        │
│                          │ │     View         │ │        │
│                          │ └──────────────────┘ │        │
│                          └──────────────────────┘        │
│                                    ▲                      │
│                                    │                      │
│                          ┌──────────────────────┐        │
│                          │ Service Principal    │        │
│                          │ (wiv_account)        │        │
│                          │ + Managed Identity   │        │
│                          └──────────────────────┘        │
└─────────────────────────────────────────────────────────┘
```

## 🔐 Authentication & Security

### Managed Identity (Primary Method)
- **No tokens required** - Uses Azure's built-in identity system
- **Never expires** - No maintenance needed
- **Direct access** - Uses `abfss://` protocol for Data Lake Gen2
- **Best practice** - Microsoft recommended approach

### Service Principal Roles
- Cost Management Reader
- Monitoring Reader  
- Storage Blob Data Reader (for Managed Identity)
- Storage Blob Data Contributor
- Contributor
- Synapse Administrator
- Synapse SQL Administrator
- Synapse Contributor

## 📊 Querying Billing Data

### Option 1: Synapse Studio (Web UI)
1. Navigate to https://web.azuresynapse.net
2. Select your workspace: `wiv-synapse-billing`
3. Open a new SQL script
4. Connect to `Built-in` serverless SQL pool
5. Run queries:

```sql
-- Get all billing data
SELECT * FROM BillingAnalytics.dbo.BillingData

-- Daily cost summary
SELECT 
    CAST(date AS DATE) as BillingDate,
    SUM(CAST(costInUsd AS FLOAT)) as DailyCostUSD,
    COUNT(DISTINCT ResourceId) as ResourceCount
FROM BillingAnalytics.dbo.BillingData
GROUP BY CAST(date AS DATE)
ORDER BY BillingDate DESC
```

### Option 2: Python Client
```python
python3 synapse_remote_query_client.py
```

This will show:
- Daily costs for the last 7 days
- Resource group billing summary
- Top 10 resources by cost
- Monthly cost trends

### Option 3: Test Connection
```python
python3 test_synapse_connection.py
```

Validates:
- Database connectivity
- View functionality
- Data availability

## 🛠️ Enhanced Features

### Robust Retry Logic
- **2.5-minute initial wait** after Synapse creation
- **10 database creation attempts** with progressive backoff
- **Smart error detection** for Azure initialization issues
- **Automatic permission propagation** handling

### Automatic Billing Export
- Triggers immediately after setup
- Runs daily at midnight UTC
- Data available in 5-30 minutes
- Month-to-date cumulative data

## 📁 Generated Files

| File | Purpose |
|------|---------|
| `synapse_config.py` | Python client configuration |
| `billing_queries.sql` | Sample SQL queries |
| `synapse_billing_setup.sql` | Manual backup SQL script |

## 🔍 Troubleshooting

### "Could not obtain exclusive lock on database"
This is normal during initial Azure setup. The script automatically retries up to 10 times with progressive delays.

### "Login failed for user"
Permissions are still propagating. The script retries automatically with 15-second delays.

### "Content of directory cannot be listed"
No billing data exported yet. Wait 5-30 minutes after setup for first export.

### Manual Database Setup
If automated setup fails, use Synapse Studio:
1. Open the workspace in Synapse Studio
2. Run the SQL from `synapse_billing_setup.sql`

## 📈 Sample Output

```
Daily Costs (Last 7 Days):
  BillingDate  DailyCostUSD  ResourceCount
0  2025-08-14      0.005827              2
1  2025-08-13      0.009680              2
2  2025-08-12      0.009680              2

Top Resources by Cost:
  ResourceId                     TotalCostUSD  ServiceFamily
0  /subscriptions/.../storage    0.087234      Storage
1  /subscriptions/.../compute    0.044432      Compute
```

## 🚀 Benefits of This Solution

1. **Zero Maintenance** - Managed Identity never expires
2. **Fully Automated** - Single script sets up everything
3. **Production Ready** - Robust error handling and retries
4. **Cost Visibility** - Daily insights into Azure spending
5. **Scalable** - Serverless architecture grows with your data
6. **Secure** - No hardcoded credentials or tokens

## 📝 Notes

- First billing export takes 5-30 minutes
- Daily exports run at midnight UTC
- Each export contains month-to-date cumulative data
- Synapse serverless SQL pool scales automatically
- No dedicated SQL pools required (cost-effective)

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

## 📄 License

This project is part of the Azure Onboarding suite by wiv.ai

