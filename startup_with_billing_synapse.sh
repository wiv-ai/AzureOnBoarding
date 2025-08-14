#!/bin/bash

echo ""
echo "🚀 Azure Onboarding Script with Billing & Synapse Starting..."
echo "--------------------------------------"

# Login to Azure (if needed)
# az login

# Fetch and list all subscriptions
SUBSCRIPTIONS=$(az account list --query '[].{name:name, id:id}' -o tsv)

echo "📦 Available Azure subscriptions:"
echo "Name      ID"
echo "--------  ------------------------------------"
echo "$SUBSCRIPTIONS"

# Prompt user to pick subscription for creating the app
read -p "🔹 Enter the Subscription ID to use for creating the application: " APP_SUBSCRIPTION_ID
az account set --subscription "$APP_SUBSCRIPTION_ID"

# Get Tenant ID
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Tenant ID: $TENANT_ID"

# App registration and service principal
APP_DISPLAY_NAME="wiv_account"
echo ""
echo "🔐 Checking for service principal '$APP_DISPLAY_NAME'..."
APP_ID=$(az ad sp list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv)

if [ -z "$APP_ID" ]; then
  echo "🔧 Creating new App Registration..."
  APP_ID=$(az ad app create --display-name "$APP_DISPLAY_NAME" --query appId -o tsv)
  az ad sp create --id "$APP_ID" > /dev/null
  echo "✅ Service principal created. App ID: $APP_ID"
  
  # Create client secret for new app
  echo ""
  echo "🔑 Creating client secret..."
  if date --version >/dev/null 2>&1; then
      END_DATE=$(date -d "+2 years" +"%Y-%m-%d")
  else
      END_DATE=$(date -v +2y +"%Y-%m-%d")
  fi
  CLIENT_SECRET=$(az ad app credential reset --id "$APP_ID" --end-date "$END_DATE" --query password -o tsv)
  echo "✅ Client secret created successfully"
else
  echo "✅ Service principal already exists. App ID: $APP_ID"
  echo "⏭️  Skipping app creation and client secret generation..."
  CLIENT_SECRET=""
  echo "ℹ️  Note: Client secret not available. Remote access features will require manual configuration."
fi

# Assign roles to all subscriptions
echo ""
echo "🔒 Do you want to assign roles to all subscriptions or only specific ones? (all/specific): "
read SCOPE_CHOICE

if [[ "$SCOPE_CHOICE" =~ ^[Aa]ll$ ]]; then
  echo "🔒 Assigning roles to all subscriptions..."
  SUBSCRIPTIONS_TO_PROCESS=$(az account list --query '[].id' -o tsv)
else
  echo "🔒 Enter comma-separated list of subscription IDs to assign roles to (or press Enter to use the same subscription): "
  read SPECIFIC_SUBSCRIPTIONS

  if [ -z "$SPECIFIC_SUBSCRIPTIONS" ]; then
    SUBSCRIPTIONS_TO_PROCESS="$APP_SUBSCRIPTION_ID"
  else
    SUBSCRIPTIONS_TO_PROCESS=$(echo $SPECIFIC_SUBSCRIPTIONS | tr ',' ' ')
  fi
fi

for SUBSCRIPTION_ID in $SUBSCRIPTIONS_TO_PROCESS; do
  echo "Processing subscription: $SUBSCRIPTION_ID"

  # Assign Cost Management Reader role
  echo "  - Assigning Cost Management Reader..."
  az role assignment create --assignee "$APP_ID" --role "Cost Management Reader" --scope "/subscriptions/$SUBSCRIPTION_ID" --only-show-errors

  # Assign Monitoring Reader role
  echo "  - Assigning Monitoring Reader..."
  az role assignment create --assignee "$APP_ID" --role "Monitoring Reader" --scope "/subscriptions/$SUBSCRIPTION_ID" --only-show-errors

  # Assign Storage Blob Data Contributor role for billing exports
  echo "  - Assigning Storage Blob Data Contributor..."
  az role assignment create --assignee "$APP_ID" --role "Storage Blob Data Contributor" --scope "/subscriptions/$SUBSCRIPTION_ID" --only-show-errors

  # Assign Contributor role for Synapse workspace management
  echo "  - Assigning Contributor role for Synapse management..."
  az role assignment create --assignee "$APP_ID" --role "Contributor" --scope "/subscriptions/$SUBSCRIPTION_ID" --only-show-errors

  echo "  ✅ Done with subscription: $SUBSCRIPTION_ID"
done

# ===========================
# BILLING EXPORT CONFIGURATION
# ===========================
echo ""
echo "💰 Configuring Azure Cost Management Billing Export..."
echo "--------------------------------------"

# Prompt for resource group
read -p "🔹 Enter Resource Group name for billing resources (or press Enter for 'rg-billing-export'): " BILLING_RG
BILLING_RG=${BILLING_RG:-"rg-billing-export"}

# Create resource group if it doesn't exist
echo "📁 Creating/Checking resource group '$BILLING_RG'..."
az group create --name "$BILLING_RG" --location "eastus" --only-show-errors

# Create storage account for billing exports
STORAGE_ACCOUNT_NAME="billingstorage$(date +%s | tail -c 6)"
echo "📦 Creating storage account '$STORAGE_ACCOUNT_NAME'..."
az storage account create \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$BILLING_RG" \
    --location "eastus" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --only-show-errors

# Create container for billing exports
CONTAINER_NAME="billing-exports"
echo "📂 Creating container '$CONTAINER_NAME'..."
STORAGE_KEY=$(az storage account keys list \
    --resource-group "$BILLING_RG" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --query '[0].value' -o tsv)

az storage container create \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --account-key "$STORAGE_KEY" \
    --only-show-errors

# Create daily billing export
EXPORT_NAME="DailyBillingExport"
echo "📊 Creating daily billing export '$EXPORT_NAME'..."

# Get storage account resource ID
STORAGE_RESOURCE_ID=$(az storage account show \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$BILLING_RG" \
    --query id -o tsv)

# Create the export using REST API (as CLI doesn't have direct support)
az rest --method PUT \
    --uri "https://management.azure.com/subscriptions/$APP_SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME?api-version=2021-10-01" \
    --body @- <<EOF
{
  "properties": {
    "schedule": {
      "status": "Active",
      "recurrence": "Daily",
      "recurrencePeriod": {
        "from": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "to": "$(date -u -d '+5 years' +%Y-%m-%dT%H:%M:%SZ)"
      }
    },
    "format": "Csv",
    "deliveryInfo": {
      "destination": {
        "resourceId": "$STORAGE_RESOURCE_ID",
        "container": "$CONTAINER_NAME",
        "rootFolderPath": "billing-data"
      }
    },
    "definition": {
      "type": "ActualCost",
      "timeframe": "MonthToDate",
      "dataSet": {
        "granularity": "Daily",
        "configuration": {
          "columns": [
            "Date",
            "ServiceName",
            "ServiceTier",
            "MeterCategory",
            "MeterSubCategory",
            "Meter",
            "AccountName",
            "DepartmentName",
            "CostCenter",
            "ResourceGroup",
            "ResourceLocation",
            "ConsumedService",
            "ResourceId",
            "ResourceType",
            "ChargeType",
            "PublisherType",
            "Quantity",
            "Cost",
            "CostUSD",
            "PayGPrice",
            "BillingCurrency"
          ]
        }
      }
    }
  }
}
EOF

echo "✅ Daily billing export configured successfully"

# ===========================
# SYNAPSE WORKSPACE SETUP
# ===========================
echo ""
echo "🔷 Setting up Azure Synapse Analytics Workspace..."
echo "--------------------------------------"

# Prompt for Synapse workspace name
read -p "🔹 Enter Synapse workspace name (or press Enter for 'synapse-billing-analytics'): " SYNAPSE_WORKSPACE
SYNAPSE_WORKSPACE=${SYNAPSE_WORKSPACE:-"synapse-billing-analytics"}

# Create Synapse workspace
echo "🏗️ Creating Synapse workspace '$SYNAPSE_WORKSPACE'..."

# Create Data Lake Storage Gen2 for Synapse
SYNAPSE_STORAGE="synapsedl$(date +%s | tail -c 6)"
echo "📦 Creating Data Lake Storage Gen2 account '$SYNAPSE_STORAGE'..."
az storage account create \
    --name "$SYNAPSE_STORAGE" \
    --resource-group "$BILLING_RG" \
    --location "eastus" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --hierarchical-namespace true \
    --only-show-errors

# Create filesystem for Synapse
FILESYSTEM_NAME="synapsefilesystem"
echo "📂 Creating filesystem '$FILESYSTEM_NAME'..."
az storage fs create \
    --name "$FILESYSTEM_NAME" \
    --account-name "$SYNAPSE_STORAGE" \
    --auth-mode login \
    --only-show-errors

# Create Synapse workspace
echo "🔧 Creating Synapse workspace..."
SQL_ADMIN_USER="sqladminuser"
SQL_ADMIN_PASSWORD="P@ssw0rd$(date +%s | tail -c 6)!"

az synapse workspace create \
    --name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --storage-account "$SYNAPSE_STORAGE" \
    --file-system "$FILESYSTEM_NAME" \
    --sql-admin-login-user "$SQL_ADMIN_USER" \
    --sql-admin-login-password "$SQL_ADMIN_PASSWORD" \
    --location "eastus" \
    --only-show-errors

# Wait for workspace to be created
echo "⏳ Waiting for Synapse workspace to be fully provisioned..."
az synapse workspace wait --resource-group "$BILLING_RG" --name "$SYNAPSE_WORKSPACE" --created

# Create firewall rule to allow Azure services
echo "🔥 Configuring firewall rules..."
az synapse workspace firewall-rule create \
    --name "AllowAllAzureServices" \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --start-ip-address "0.0.0.0" \
    --end-ip-address "0.0.0.0" \
    --only-show-errors

# Create firewall rule to allow all IPs (for remote access)
echo "🌐 Creating firewall rule for remote access..."
az synapse workspace firewall-rule create \
    --name "AllowAllIPs" \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --start-ip-address "0.0.0.0" \
    --end-ip-address "255.255.255.255" \
    --only-show-errors

# ===========================
# SYNAPSE PERMISSIONS SETUP
# ===========================
echo ""
echo "🔐 Configuring Synapse permissions for wiv_account..."
echo "--------------------------------------"

# Get Synapse workspace resource ID
SYNAPSE_RESOURCE_ID=$(az synapse workspace show \
    --name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --query id -o tsv)

# Assign Synapse Administrator role to the service principal
echo "👤 Assigning Synapse Administrator role..."
az synapse role assignment create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --role "Synapse Administrator" \
    --assignee "$APP_ID" \
    --only-show-errors

# Assign Synapse SQL Administrator role
echo "🗄️ Assigning Synapse SQL Administrator role..."
az synapse role assignment create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --role "Synapse SQL Administrator" \
    --assignee "$APP_ID" \
    --only-show-errors

# Assign Synapse Contributor role
echo "✏️ Assigning Synapse Contributor role..."
az synapse role assignment create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --role "Synapse Contributor" \
    --assignee "$APP_ID" \
    --only-show-errors

# Create linked service for billing storage
echo "🔗 Creating linked service to billing storage..."
LINKED_SERVICE_NAME="BillingStorageLinkedService"

# Get storage account key
BILLING_STORAGE_KEY=$(az storage account keys list \
    --resource-group "$BILLING_RG" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --query '[0].value' -o tsv)

# Create linked service JSON
cat > linked_service.json <<EOF
{
  "name": "$LINKED_SERVICE_NAME",
  "properties": {
    "type": "AzureBlobStorage",
    "typeProperties": {
      "connectionString": "DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT_NAME;AccountKey=$BILLING_STORAGE_KEY;EndpointSuffix=core.windows.net"
    }
  }
}
EOF

# Create the linked service
az synapse linked-service create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --name "$LINKED_SERVICE_NAME" \
    --file @linked_service.json \
    --only-show-errors

# Clean up temp file
rm linked_service.json

# Create SQL script for analyzing billing data
echo "📝 Creating SQL script for billing analysis..."
SQL_SCRIPT_NAME="AnalyzeBillingData"

cat > billing_analysis.sql <<'EOF'
-- Create external data source for billing exports
IF NOT EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'BillingStorage')
BEGIN
    CREATE EXTERNAL DATA SOURCE BillingStorage
    WITH (
        TYPE = HADOOP,
        LOCATION = 'wasbs://billing-exports@STORAGE_ACCOUNT_NAME.blob.core.windows.net'
    );
END;

-- Create external file format for CSV
IF NOT EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'CSVFormat')
BEGIN
    CREATE EXTERNAL FILE FORMAT CSVFormat
    WITH (
        FORMAT_TYPE = DELIMITEDTEXT,
        FORMAT_OPTIONS (
            FIELD_TERMINATOR = ',',
            STRING_DELIMITER = '"',
            FIRST_ROW = 2,
            USE_TYPE_DEFAULT = TRUE
        )
    );
END;

-- Query to analyze daily costs
SELECT 
    Date,
    ServiceName,
    ResourceGroup,
    SUM(CAST(Cost AS FLOAT)) AS TotalCost,
    SUM(CAST(CostUSD AS FLOAT)) AS TotalCostUSD
FROM 
    OPENROWSET(
        BULK 'billing-data/*.csv',
        DATA_SOURCE = 'BillingStorage',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        HEADER_ROW = TRUE
    ) AS [billing]
GROUP BY 
    Date, ServiceName, ResourceGroup
ORDER BY 
    Date DESC, TotalCostUSD DESC;

-- Query to get top 10 most expensive resources
SELECT TOP 10
    ResourceId,
    ResourceType,
    ServiceName,
    SUM(CAST(CostUSD AS FLOAT)) AS TotalCostUSD
FROM 
    OPENROWSET(
        BULK 'billing-data/*.csv',
        DATA_SOURCE = 'BillingStorage',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        HEADER_ROW = TRUE
    ) AS [billing]
WHERE 
    Date >= DATEADD(day, -30, GETDATE())
GROUP BY 
    ResourceId, ResourceType, ServiceName
ORDER BY 
    TotalCostUSD DESC;
EOF

# Replace placeholder with actual storage account name
sed -i "s/STORAGE_ACCOUNT_NAME/$STORAGE_ACCOUNT_NAME/g" billing_analysis.sql

# Upload SQL script to Synapse (Note: This requires Synapse Studio or REST API)
echo "📤 SQL script created locally. Upload to Synapse Studio for execution."

# Optional: Microsoft Graph permissions
echo ""
read -p "Do you want to grant Microsoft Graph permissions (e.g., Directory.Read.All)? (y/n): " GRANT_PERMS

if [[ "$GRANT_PERMS" =~ ^[Yy]$ ]]; then
    echo "📘 Granting Microsoft Graph permissions..."

    echo "🔹 Adding Directory.Read.All permission..."
    az ad app permission add \
        --id "$APP_ID" \
        --api 00000003-0000-0000-c000-000000000000 \
        --api-permissions 7ab1d382-f21e-4acd-a863-ba3e13f7da61=Role

    echo "🔹 Granting the permission..."
    az ad app permission grant \
        --id "$APP_ID" \
        --api 00000003-0000-0000-c000-000000000000 \
        --scope "https://graph.microsoft.com/Directory.Read.All"

    echo "🔹 Requesting admin consent..."
    az ad app permission admin-consent --id "$APP_ID"
    if [ $? -eq 0 ]; then
        echo "✅ Admin consent granted successfully."
    else
        echo "⚠️  Admin consent failed. You may need to manually grant consent via Azure Portal."
    fi
else
    echo "🚫 Skipping Microsoft Graph permission grant."
fi

# ===========================
# PYTHON SCRIPT FOR REMOTE ACCESS
# ===========================
echo ""
echo "🐍 Creating Python script for remote Synapse access..."
cat > synapse_remote_query.py <<EOF
#!/usr/bin/env python3
"""
Remote Synapse Query Script
This script allows remote execution of SQL queries on Azure Synapse Analytics
"""

import os
from azure.identity import ClientSecretCredential
from azure.synapse.spark import SparkClient
import pyodbc
import pandas as pd

# Configuration
TENANT_ID = "$TENANT_ID"
CLIENT_ID = "$APP_ID"
CLIENT_SECRET = "$CLIENT_SECRET"
SYNAPSE_WORKSPACE = "$SYNAPSE_WORKSPACE"
SQL_ENDPOINT = "$SYNAPSE_WORKSPACE.sql.azuresynapse.net"
DATABASE = "master"

def get_synapse_connection():
    """Create connection to Synapse SQL pool"""
    # Get access token
    credential = ClientSecretCredential(
        tenant_id=TENANT_ID,
        client_id=CLIENT_ID,
        client_secret=CLIENT_SECRET
    )
    
    token = credential.get_token("https://database.windows.net/.default")
    
    # Create connection string
    conn_str = (
        f"DRIVER={{ODBC Driver 17 for SQL Server}};"
        f"SERVER={SQL_ENDPOINT};"
        f"DATABASE={DATABASE};"
        f"Authentication=ActiveDirectoryServicePrincipal;"
        f"UID={CLIENT_ID};"
        f"PWD={CLIENT_SECRET};"
    )
    
    return pyodbc.connect(conn_str)

def execute_query(query):
    """Execute a SQL query on Synapse"""
    try:
        conn = get_synapse_connection()
        df = pd.read_sql(query, conn)
        conn.close()
        return df
    except Exception as e:
        print(f"Error executing query: {e}")
        return None

# Example queries
def get_daily_costs(days=30):
    """Get daily costs for the last N days"""
    query = f"""
    SELECT 
        Date,
        SUM(CAST(CostUSD AS FLOAT)) AS TotalCostUSD
    FROM 
        OPENROWSET(
            BULK 'billing-data/*.csv',
            DATA_SOURCE = 'BillingStorage',
            FORMAT = 'CSV',
            PARSER_VERSION = '2.0',
            HEADER_ROW = TRUE
        ) AS [billing]
    WHERE 
        Date >= DATEADD(day, -{days}, GETDATE())
    GROUP BY Date
    ORDER BY Date DESC
    """
    return execute_query(query)

def get_top_expensive_services(days=30):
    """Get top 10 most expensive services"""
    query = f"""
    SELECT TOP 10
        ServiceName,
        SUM(CAST(CostUSD AS FLOAT)) AS TotalCostUSD
    FROM 
        OPENROWSET(
            BULK 'billing-data/*.csv',
            DATA_SOURCE = 'BillingStorage',
            FORMAT = 'CSV',
            PARSER_VERSION = '2.0',
            HEADER_ROW = TRUE
        ) AS [billing]
    WHERE 
        Date >= DATEADD(day, -{days}, GETDATE())
    GROUP BY ServiceName
    ORDER BY TotalCostUSD DESC
    """
    return execute_query(query)

if __name__ == "__main__":
    print("Testing Synapse connection...")
    
    # Test queries
    print("\n📊 Daily Costs (Last 7 days):")
    daily_costs = get_daily_costs(7)
    if daily_costs is not None:
        print(daily_costs)
    
    print("\n💰 Top Expensive Services (Last 30 days):")
    top_services = get_top_expensive_services(30)
    if top_services is not None:
        print(top_services)
EOF

# Create requirements.txt for Python dependencies
echo "📦 Creating requirements.txt for Python dependencies..."
cat > requirements.txt <<EOF
azure-identity
azure-synapse-spark
pyodbc
pandas
EOF

# Final output
echo ""
echo "✅ Azure Onboarding with Billing Export and Synapse Complete"
echo "============================================================"
echo "📄 Tenant ID:                $TENANT_ID"
echo "📄 App (Client) ID:          $APP_ID"
echo "📄 Client Secret:            $CLIENT_SECRET"
echo ""
echo "💾 Storage Configuration:"
echo "   - Resource Group:         $BILLING_RG"
echo "   - Storage Account:        $STORAGE_ACCOUNT_NAME"
echo "   - Container:              $CONTAINER_NAME"
echo "   - Export Name:            $EXPORT_NAME"
echo ""
echo "🔷 Synapse Configuration:"
echo "   - Workspace:              $SYNAPSE_WORKSPACE"
echo "   - SQL Endpoint:           $SYNAPSE_WORKSPACE.sql.azuresynapse.net"
echo "   - SQL Admin User:         $SQL_ADMIN_USER"
echo "   - SQL Admin Password:     $SQL_ADMIN_PASSWORD"
echo "   - Data Lake Storage:      $SYNAPSE_STORAGE"
echo ""
echo "📄 Assigned Roles:"
echo "   - Cost Management Reader"
echo "   - Monitoring Reader"
echo "   - Storage Blob Data Contributor"
echo "   - Contributor"
echo "   - Synapse Administrator"
echo "   - Synapse SQL Administrator"
echo "   - Synapse Contributor"
echo ""
echo "📝 Next Steps:"
echo "   1. The billing export will run daily and store data in: $STORAGE_ACCOUNT_NAME/$CONTAINER_NAME/billing-data/"
echo "   2. Use Synapse Studio to run the SQL queries in 'billing_analysis.sql'"
echo "   3. Use 'synapse_remote_query.py' for remote access to Synapse"
echo "   4. Install Python dependencies: pip install -r requirements.txt"
echo ""
echo "🔗 Synapse Studio URL: https://web.azuresynapse.net"
echo "============================================================"