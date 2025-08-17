# Azure Billing Analytics with Synapse

A comprehensive solution for automated Azure billing data export and analysis using Azure Synapse Analytics with **Managed Identity** authentication - no tokens, no expiration, no maintenance required!

## 🚀 Features

- **Automated Daily Billing Export** - Configures Azure Cost Management to export billing data daily
- **Support for Existing Exports** - Use existing billing exports from any subscription
- **Cross-Subscription Support** - Access billing data from different subscriptions
- **Automatic Data Deduplication** - Smart view queries only the latest export to prevent duplication
- **Azure Synapse Analytics Integration** - Serverless SQL pool for querying billing data
- **Managed Identity Authentication** - No SAS tokens or keys to manage, never expires
- **Service Principal Setup** - Automated creation and configuration of `wiv_account`
- **Comprehensive Permissions** - All required roles automatically assigned
- **Remote Query Support** - Python client for programmatic access
- **Multiple SQL Execution Methods** - Fallback options ensure database setup completes
- **Single-Run Setup** - Enhanced retry logic ensures completion in one execution
- **Idempotent Design** - Safe to run multiple times

## 📋 Prerequisites

- Azure CLI installed and configured
- Active Azure subscription
- Bash shell environment
- Python 3.x (for remote queries)
- Optional: `sqlcmd` for direct SQL execution (auto-installed if missing)

## 🔧 Quick Start

### Option 1: Fresh Setup with New Billing Export

1. **Clone the repository:**
```bash
git clone -b feature/billing-export-synapse https://github.com/wiv-ai/AzureOnBoarding.git
cd AzureOnBoarding
```

2. **Run the setup script:**
```bash
./startup_with_billing_synapse.sh
```

When prompted:
```
Use existing billing export? (y/n): n
```

The script will create everything from scratch.

### Option 2: Use Existing Billing Export

```bash
./startup_with_billing_synapse.sh
```

When prompted:
```
Use existing billing export? (y/n): y
Storage Account Name: myorgstorage123
Storage Account Resource Group: billing-rg
Storage Account Subscription ID: [Enter or press Enter for current]
Container Name: cost-exports
Export folder path: monthly-exports/ActualCost
```

The script will:
- Verify access to existing storage
- Configure Synapse to read from your existing exports
- Skip creating duplicate billing exports

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Subscription(s)                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐        ┌──────────────────────┐               │
│  │ Cost Mgmt    │───────▶│ Storage Account      │               │
│  │ Daily Export │        │ (new or existing)    │               │
│  └──────────────┘        └──────────────────────┘               │
│                                    │                              │
│                          Cross-subscription                       │
│                            access supported                       │
│                                    ▼                              │
│                          ┌──────────────────────┐                │
│                          │ Synapse Workspace    │                │
│                          │ (wiv-synapse-billing)│                │
│                          │                      │                │
│                          │ ┌──────────────────┐ │                │
│                          │ │ BillingAnalytics │ │                │
│                          │ │    Database      │ │                │
│                          │ └──────────────────┘ │                │
│                          │          │           │                │
│                          │          ▼           │                │
│                          │ ┌──────────────────┐ │                │
│                          │ │  BillingData     │ │                │
│                          │ │  View (Deduped)  │ │                │
│                          │ └──────────────────┘ │                │
│                          └──────────────────────┘                │
│                                    ▲                              │
│                                    │                              │
│                          ┌──────────────────────┐                │
│                          │ Service Principal    │                │
│                          │ (wiv_account)        │                │
│                          │ + Managed Identity   │                │
│                          └──────────────────────┘                │
└─────────────────────────────────────────────────────────────────┘
```

## 🔐 Authentication & Security

### Managed Identity (Primary Method)
- **No tokens required** - Uses Azure's built-in identity system
- **Never expires** - No maintenance needed
- **Direct access** - Uses `abfss://` protocol for Data Lake Gen2
- **Cross-subscription** - Can access storage in different subscriptions
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

## 📊 Understanding Billing Data

### The Deduplication Challenge
Azure Cost Management exports are **cumulative month-to-date**:
- **Day 1**: Contains only Day 1 costs
- **Day 2**: Contains Day 1 + Day 2 costs
- **Day 30**: Contains entire month's data

**⚠️ Problem**: Querying all files causes massive duplication!

### The Solution: Automatic Deduplication
The `BillingData` view automatically queries only the **latest export file**:

```sql
-- The view handles deduplication internally
SELECT * FROM BillingAnalytics.dbo.BillingData
-- This automatically returns only the latest data!
```

No need for complex CTEs or manual filtering - it's built-in!

## 💰 Cost Analysis

### Deployment Costs (Monthly)

| Organization Size | Resources | Data Size | Query Cost | Storage Cost | **Total** |
|-------------------|-----------|-----------|------------|--------------|-----------|
| Small | <100 | <1GB | $0.01 | $0.05 | **$0.06** |
| Medium | 500-1000 | 10GB | $1.50 | $0.10 | **$1.60** |
| Large | 5000-10000 | 100GB | $15.00 | $0.50 | **$15.50** |
| Enterprise | 100000+ | 1TB+ | $150.00 | $5.00 | **$155.00** |

**Key Points:**
- Synapse Serverless: **$5 per TB queried**
- Storage: **$0.02 per GB/month**
- No idle costs - pay only when querying
- No minimum fees or commitments

## 📊 Querying Billing Data

### Option 1: Synapse Studio (Web UI)
1. Navigate to https://web.azuresynapse.net
2. Select your workspace: `wiv-synapse-billing`
3. Open a new SQL script
4. Connect to `Built-in` serverless SQL pool
5. Run queries:

```sql
-- Get latest billing data (automatically deduplicated!)
SELECT * FROM BillingAnalytics.dbo.BillingData

-- Daily cost summary
SELECT 
    CAST(date AS DATE) as BillingDate,
    SUM(CAST(costInUsd AS FLOAT)) as DailyCostUSD,
    COUNT(DISTINCT ResourceId) as ResourceCount
FROM BillingAnalytics.dbo.BillingData
GROUP BY CAST(date AS DATE)
ORDER BY BillingDate DESC

-- Top 10 expensive resources
SELECT TOP 10
    resourceId,
    resourceGroup,
    SUM(CAST(costInUsd AS FLOAT)) as TotalCost
FROM BillingAnalytics.dbo.BillingData
GROUP BY resourceId, resourceGroup
ORDER BY TotalCost DESC
```

### Option 2: Python Client
```python
python3 synapse_remote_query_client.py
```

### Option 3: Test Connection
```python
python3 test_remote_query.py
```

## 🛠️ Export Configuration Options

### Data Type Selection

| Type | Use Case | What It Shows |
|------|----------|---------------|
| **ActualCost** (Default) | Invoice matching, showback | Real charges as on invoice |
| **AmortizedCost** | Budgeting with reservations | Spreads reservation costs |
| **Usage** | Technical analysis | Raw consumption, no costs |

### Compression Options

| Type | Storage Size | Synapse Support | Recommendation |
|------|--------------|-----------------|----------------|
| **None** (Default) | 100% | ✅ Direct query | Use this |
| **GZip** | 10-20% | ❌ Needs ETL | Only for archival |

### Dataset Versions

| Version | Schema | Columns | Future-Proof | Use When |
|---------|--------|---------|--------------|----------|
| **Legacy** (Default) | Azure-specific | 200+ | Stable | Existing systems |
| **FOCUS** | Multi-cloud standard | ~50 | ✅ | New deployments |

## 🔍 Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Could not obtain exclusive lock" | Azure initialization | Script auto-retries 10x |
| "Login failed for user" | Permission propagation | Auto-retry with delays |
| "Content cannot be listed" | No data yet | Wait 5-30 min for export |
| "Date: illegal option" | macOS date command | Script handles automatically |
| "Invalid column: CostInUsd" | Case sensitivity | Fixed to "CostInUSD" |
| "pyodbc installation failed" | Missing dependencies | Script uses fallback methods |

### Manual Fallbacks

If automated setup fails:

1. **SQL via Synapse Studio:**
   - Open workspace in Azure Portal
   - Run SQL from `synapse_billing_setup.sql`

2. **SQL via generated script:**
   ```bash
   ./complete_synapse_setup.sh
   ```

## 📈 Sample Queries

### Cost Optimization Analysis
```sql
-- Find unused resources (no cost in last 7 days)
WITH RecentCosts AS (
    SELECT DISTINCT resourceId
    FROM BillingAnalytics.dbo.BillingData
    WHERE CAST(date AS DATE) >= DATEADD(day, -7, GETDATE())
      AND CAST(costInUsd AS FLOAT) > 0
)
SELECT DISTINCT b.resourceId, b.resourceGroup
FROM BillingAnalytics.dbo.BillingData b
WHERE b.resourceId NOT IN (SELECT resourceId FROM RecentCosts)
  AND b.resourceId IS NOT NULL
```

### Department Chargeback
```sql
-- Costs by resource group (department)
SELECT 
    resourceGroup as Department,
    DATEPART(YEAR, date) as Year,
    DATEPART(MONTH, date) as Month,
    SUM(CAST(costInUsd AS FLOAT)) as MonthlyCharge
FROM BillingAnalytics.dbo.BillingData
WHERE resourceGroup IS NOT NULL
GROUP BY resourceGroup, DATEPART(YEAR, date), DATEPART(MONTH, date)
ORDER BY Year DESC, Month DESC, MonthlyCharge DESC
```

## 🚀 Benefits of This Solution

1. **Zero Maintenance** - Managed Identity never expires
2. **Automatic Deduplication** - No complex queries needed
3. **Cross-Subscription** - Centralized billing analysis
4. **Flexible Setup** - Works with new or existing exports
5. **Cost Effective** - Pay only for queries, not idle time
6. **Production Ready** - Robust error handling and retries
7. **Multiple Fallbacks** - Ensures successful deployment
8. **Fully Automated** - Single script sets up everything

## 📝 Notes

- First billing export takes 5-30 minutes
- Daily exports run at midnight UTC
- Each export contains month-to-date cumulative data
- The BillingData view automatically handles deduplication
- Synapse serverless SQL pool scales automatically
- No dedicated SQL pools required (cost-effective)
- Cross-subscription access requires proper permissions

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

## 📄 License

This project is part of the Azure Onboarding suite by wiv.ai

