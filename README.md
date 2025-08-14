# Azure Billing Analytics with Synapse - Automated Setup

## 🚀 Overview
This repository provides a fully automated solution for setting up Azure billing analytics using Azure Synapse Analytics with **Managed Identity authentication** (no tokens, never expires!). The script creates all necessary Azure resources, configures daily billing exports, and sets up a Synapse Analytics workspace for querying billing data.

## ✨ Key Features
- **Fully Automated Setup** - Single script creates everything
- **Managed Identity Authentication** - No SAS tokens, never expires
- **Daily Billing Export** - Automatic daily export to Azure Storage
- **Azure Synapse Analytics** - Serverless SQL pool for billing analysis
- **Remote Query Support** - Python client for programmatic access
- **Zero Maintenance** - Uses Azure native authentication that works forever

## 📋 Prerequisites
- Azure CLI installed and configured
- Active Azure subscription with billing data
- Permissions to create resources and assign roles
- Python 3.x (for remote query client)
- `pyodbc` and `pandas` (installed automatically by script)

## 🛠️ Components Created

### Azure Resources
- **Service Principal**: `wiv_account` for programmatic access
- **Resource Group**: `wiv-rg` for all resources
- **Storage Account**: For billing export data (Data Lake Gen2 enabled)
- **Synapse Workspace**: `wiv-synapse-billing` for analytics
- **Billing Export**: Daily automated export configuration

### Database Objects
- **Database**: `BillingAnalytics` in Synapse
- **View**: `BillingData` for querying billing information
- **Authentication**: Managed Identity with `abfss://` protocol

## 📦 Installation & Setup

### 1. Clone the Repository
```bash
git clone <repository-url>
cd <repository-directory>
```

### 2. Run the Setup Script
```bash
chmod +x startup_with_billing_synapse.sh
./startup_with_billing_synapse.sh
```

The script will:
1. Check for existing `wiv_account` service principal
2. Create resource groups and storage accounts
3. Configure daily billing export
4. Create Synapse workspace
5. Set up Managed Identity permissions
6. Create database and views automatically
7. Generate configuration files for remote access

### 3. Wait for First Export
Billing data export runs daily. Your first data will appear within 24 hours.

## 🔐 Authentication Method

### Managed Identity with abfss:// Protocol
- **No Tokens Required** - Uses Azure native authentication
- **Never Expires** - Works forever without maintenance
- **Direct Access** - Uses Data Lake Gen2 endpoint
- **Best Practice** - Microsoft recommended approach

The system uses the `abfss://` protocol to directly access storage through Managed Identity:
```sql
OPENROWSET(
    BULK 'abfss://billing-exports@storage.dfs.core.windows.net/path/*.csv',
    FORMAT = 'CSV'
)
```

## 📊 Querying Billing Data

### Option 1: Synapse Studio (Web UI)
1. Navigate to https://web.azuresynapse.net
2. Select your workspace: `wiv-synapse-billing`
3. Connect to the **Built-in** serverless SQL pool
4. Query the data:
```sql
SELECT * FROM BillingAnalytics.dbo.BillingData
WHERE date >= DATEADD(day, -30, GETDATE())
```

### Option 2: Python Client (Remote Access)
```python
from synapse_remote_query_client import SynapseAPIClient

# Client automatically uses synapse_config.py
client = SynapseAPIClient()

# Get daily costs
df = client.get_daily_costs(days_back=7)
print(df)

# Get billing summary
summary = client.get_billing_summary()
print(summary)
```

### Option 3: Direct SQL Queries
Use any SQL client that supports Azure AD authentication to connect to:
- **Server**: `wiv-synapse-billing-ondemand.sql.azuresynapse.net`
- **Database**: `BillingAnalytics`
- **Authentication**: Azure AD

## 📁 Repository Structure

```
/
├── startup_with_billing_synapse.sh    # Main setup script
├── synapse_remote_query_client.py     # Python client for remote queries
├── test_synapse_connection.py         # Connection diagnostic tool
├── synapse_config.py                  # Generated config (DO NOT COMMIT)
├── README.md                           # This file
└── .gitignore                         # Excludes sensitive files
```

## 🔧 Configuration Files

### synapse_config.py (Auto-generated)
Contains connection details and credentials. This file is:
- Generated automatically by the setup script
- Added to `.gitignore` to prevent accidental commits
- Required for the Python client to work

### Important Security Note
**Never commit `synapse_config.py` to version control!** It contains sensitive credentials.

## 🧪 Testing & Diagnostics

### Test Connection
```bash
python3 test_synapse_connection.py
```

This will:
- Verify service principal authentication
- Check database existence
- Test the BillingData view
- Display sample data if available

## 📈 Available Queries

The Python client includes pre-built queries:
- `get_daily_costs()` - Daily cost breakdown
- `get_billing_summary()` - Summary by resource group
- `get_top_resources()` - Most expensive resources
- `get_cost_by_location()` - Costs by Azure region
- `get_monthly_trend()` - Month-over-month trending

## 🚨 Troubleshooting

### Connection Timeout
- Wait 5-10 minutes after setup for permissions to propagate
- Ensure firewall rules allow your IP address
- Check service principal has correct roles

### No Billing Data
- First export takes up to 24 hours
- Check storage account for CSV files
- Verify billing export is configured in Azure Portal

### Authentication Errors
- Ensure `synapse_config.py` exists with correct credentials
- Verify service principal hasn't been deleted
- Check client secret hasn't expired (2-year default)

## 🔄 Maintenance

### No Regular Maintenance Required!
Thanks to Managed Identity:
- ✅ No token renewal needed
- ✅ No credential rotation required
- ✅ No expiration dates to track

### Only If Needed:
- **Client Secret Renewal** (every 2 years): Re-run the script
- **Add New Billing Accounts**: Re-run the script to update

## 📝 Roles & Permissions

The service principal is assigned:
- Cost Management Reader
- Monitoring Reader  
- Storage Blob Data Reader
- Synapse Administrator
- Synapse SQL Administrator
- Synapse Contributor

## 🌟 Benefits of This Solution

1. **Zero Token Management** - Managed Identity never expires
2. **Fully Automated** - Single script sets up everything
3. **Production Ready** - Follows Azure best practices
4. **Secure** - No secrets stored in code
5. **Scalable** - Serverless architecture
6. **Cost Effective** - Pay only for queries executed

## 📞 Support

For issues or questions:
1. Check the troubleshooting section
2. Run `test_synapse_connection.py` for diagnostics
3. Review Azure Portal for resource status
4. Check Synapse Studio for query errors

## 📜 License

[Your License Here]

## 🙏 Acknowledgments

Built with Azure Synapse Analytics and Azure Cost Management APIs.

