# Azure Wiv Platform

## Overview
This solution provides an automated setup for Azure cost management and billing analysis, similar to AWS Cost and Usage Reports (CUR). It creates a complete infrastructure for collecting, storing, and analyzing Azure cost data using native Azure services.

## Architecture
![Architecture Diagram](architecture.png)

## Resources Created

### Identity & Access Management
1. **Service Principal (App Registration)**
   - Name: `wiv_account`
   - Permissions:
      - Cost Management Reader
      - Storage Blob Data Reader
      - Monitoring Reader
      - Directory.Read.All (Graph API)

### Storage Layer
2. **Storage Account**
   - Name: `wiv<random>` (Data Lake Storage Gen2)
   - Features:
      - Hierarchical Namespace enabled
      - Standard LRS SKU
      - TLS 1.2
   - Containers:
      - `wiv-container` (for general storage)
      - `costs` (for cost data)

### Data Processing
3. **Azure Function App**
   - Name: `wiv-cost-export-<random>`
   - Features:
      - Python 3.9 runtime
      - Timer triggered (every 6 hours)
      - Managed Identity enabled
   - Supporting Resources:
      - Function Storage Account: `wivfunc<random>`
      - Application Insights: `wiv-cost-insights-<random>`

4. **Event Hub**
   - Namespace: `wiv-cost-events-<random>`
   - Hub Name: `cost-data`
   - SKU: Standard
   - Purpose: Real-time cost data events

### Analytics Layer
5. **Azure Synapse Analytics**
   - Workspace Name: `wiv-synapse-<random>`
   - Features:
      - Dedicated SQL Pool: `WivCostPool` (DW100c)
      - Serverless SQL Pool (default)
      - External tables for cost data
   - SQL Objects:
      - Schema: `[cost]`
      - Tables: `[cost].[dailyCosts]`
      - Views:
         - `[cost].[MonthlyCostsByService]`
         - `[cost].[DailyTrending]`
         - `[cost].[CostByTag]`

### Cost Management
6. **Cost Management Export**
   - Name: `wiv_cost_export`
   - Configuration:
      - Daily export
      - ActualCost type
      - MonthToDate timeframe
      - Custom directory structure

## Prerequisites
- Azure CLI installed and configured
- Azure subscription with Owner/Contributor access
- `sqlcmd` utility installed for database operations
- `jq` installed for JSON processing

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd azure-wiv-platform
```

2. Make the script executable:
```bash
chmod +x AzureWivOnBoardingNew.sh
```

3. Run the script:
```bash
./AzureWivOnBoardingNew.sh
```

4. Follow the prompts to:
   - Login to Azure
   - Select subscription
   - Provide resource group name
   - Select region

## Credentials Management
After successful deployment, credentials are stored in `wiv_credentials.txt` with restricted permissions (600). This file contains:
- Service Principal credentials
- Storage account details
- Synapse SQL connection information
- Function App configuration

## Data Flow
1. Cost Management API exports daily cost data to blob storage
2. Azure Function processes the data every 6 hours:
   - Reads from Cost Management API
   - Transforms data to Parquet format
   - Stores in Data Lake with partitioned structure
   - Sends event to Event Hub
3. Synapse Analytics provides SQL views for analysis

## Available Analytics Views

### Monthly Costs by Service
```sql
SELECT * FROM [cost].[MonthlyCostsByService]
```
Provides monthly cost aggregation by Azure service type.

### Daily Cost Trending
```sql
SELECT * FROM [cost].[DailyTrending]
```
Shows daily costs with 30-day moving average.

### Tag-based Cost Analysis
```sql
SELECT * FROM [cost].[CostByTag]
```
Analyzes costs based on resource tags and environment.

## Monitoring
- Function App execution can be monitored through Application Insights
- Cost export status available in Azure Portal
- Event Hub captures real-time cost data events

## Security Considerations
- All services use Managed Identities where possible
- Storage account configured with minimum TLS 1.2
- Synapse workspace accessible through firewall rules
- All secrets stored in restricted access file

## Troubleshooting
1. Check Function App logs in Application Insights
2. Verify Cost Management export status in Azure Portal
3. Check Event Hub metrics for data flow
4. Review Synapse external table queries for data access

## Contributing
Please refer to CONTRIBUTING.md for guidelines.

## License
This project is licensed under the MIT License - see the LICENSE file for details.