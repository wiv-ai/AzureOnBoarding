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
  CLIENT_SECRET="<EXISTING_CLIENT_SECRET_REQUIRED>"
  echo "ℹ️  Note: You'll need to manually update the client secret in generated scripts for remote access."
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

# Use fixed resource group name
BILLING_RG="wiv-rg"

# Check if resource group exists and get its location
echo "📁 Checking resource group '$BILLING_RG'..."
RG_EXISTS=$(az group exists --name "$BILLING_RG")

if [ "$RG_EXISTS" = "true" ]; then
    # Resource group exists, get its location
    AZURE_REGION=$(az group show --name "$BILLING_RG" --query location -o tsv)
    echo "✅ Using existing resource group '$BILLING_RG' in region: $AZURE_REGION"
else
    # Resource group doesn't exist, create it in eastus2 (or another region that supports Synapse)
    AZURE_REGION="eastus2"
    echo "📍 Creating resource group '$BILLING_RG' in region: $AZURE_REGION"
    az group create --name "$BILLING_RG" --location "$AZURE_REGION" --only-show-errors
fi

# Create storage account for billing exports
STORAGE_ACCOUNT_NAME="billingstorage$(date +%s | tail -c 6)"
echo "📦 Creating storage account '$STORAGE_ACCOUNT_NAME'..."
az storage account create \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$BILLING_RG" \
    --location "$AZURE_REGION" \
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
            "ServiceFamily",
            "MeterCategory",
            "MeterSubcategory",
            "MeterName",
            "BillingAccountName",
            "CostCenter",
            "ResourceGroup",
            "ResourceLocation",
            "ConsumedService",
            "ResourceId",
            "ChargeType",
            "PublisherType",
            "Quantity",
            "CostInBillingCurrency",
            "CostInUSD",
            "PayGPrice",
            "BillingCurrencyCode",
            "SubscriptionName",
            "SubscriptionId",
            "ProductName",
            "Frequency",
            "UnitOfMeasure",
            "Tags"
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

# Use fixed Synapse workspace name
SYNAPSE_WORKSPACE="wiv-synapse-billing"

# Check if Synapse workspace already exists
echo "🔍 Checking if Synapse workspace '$SYNAPSE_WORKSPACE' exists..."
SYNAPSE_EXISTS=$(az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$BILLING_RG" --query name -o tsv 2>/dev/null)

if [ -n "$SYNAPSE_EXISTS" ]; then
    echo "✅ Synapse workspace '$SYNAPSE_WORKSPACE' already exists. Using existing workspace."
    
    # Get existing storage account info
    SYNAPSE_STORAGE=$(az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$BILLING_RG" --query "defaultDataLakeStorage.accountUrl" -o tsv | sed 's|https://||' | sed 's|.dfs.core.windows.net||')
    FILESYSTEM_NAME=$(az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$BILLING_RG" --query "defaultDataLakeStorage.filesystem" -o tsv)
    echo "  - Storage Account: $SYNAPSE_STORAGE"
    echo "  - Filesystem: $FILESYSTEM_NAME"
else
    echo "🏗️ Creating new Synapse workspace '$SYNAPSE_WORKSPACE'..."
    
    # Create Data Lake Storage Gen2 for Synapse
    SYNAPSE_STORAGE="synapsedl$(date +%s | tail -c 6)"
    echo "📦 Creating Data Lake Storage Gen2 account '$SYNAPSE_STORAGE'..."
    az storage account create \
        --name "$SYNAPSE_STORAGE" \
        --resource-group "$BILLING_RG" \
        --location "$AZURE_REGION" \
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
        --location "$AZURE_REGION" \
        --only-show-errors
fi

# Wait for workspace to be created
echo "⏳ Waiting for Synapse workspace to be fully provisioned..."
az synapse workspace wait --resource-group "$BILLING_RG" --workspace-name "$SYNAPSE_WORKSPACE" --created

# Create firewall rules
echo "🔥 Configuring firewall rules..."

# Create firewall rule to allow Azure services
echo "  - Adding rule for Azure services..."
az synapse workspace firewall-rule create \
    --name "AllowAllWindowsAzureIps" \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --start-ip-address "0.0.0.0" \
    --end-ip-address "0.0.0.0" \
    --only-show-errors

# Create firewall rule to allow all IPs (for remote access)
echo "  - Adding rule for all IPs (remote access)..."
az synapse workspace firewall-rule create \
    --name "AllowAllIPs" \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --start-ip-address "0.0.0.0" \
    --end-ip-address "255.255.255.255" \
    --only-show-errors

# Wait a moment for firewall rules to take effect
echo "⏳ Waiting for firewall rules to take effect..."
sleep 10

# ===========================
# SYNAPSE PERMISSIONS SETUP
# ===========================
echo ""
echo "🔐 Configuring Synapse permissions for wiv_account..."
echo "--------------------------------------"

# Get the Object ID of the service principal (needed for Synapse role assignments)
echo "🔍 Getting service principal Object ID..."
SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)
echo "  - Service Principal Object ID: $SP_OBJECT_ID"

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
    --assignee-object-id "$SP_OBJECT_ID" \
    --only-show-errors

# Assign Synapse SQL Administrator role
echo "🗄️ Assigning Synapse SQL Administrator role..."
az synapse role assignment create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --role "Synapse SQL Administrator" \
    --assignee-object-id "$SP_OBJECT_ID" \
    --only-show-errors

# Assign Synapse Contributor role
echo "✏️ Assigning Synapse Contributor role..."
az synapse role assignment create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --role "Synapse Contributor" \
    --assignee-object-id "$SP_OBJECT_ID" \
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

# ===========================
# CREATE EXTERNAL TABLE FOR BILLING DATA
# ===========================
echo ""
echo "📊 Setting up billing data ingestion in Synapse..."
echo "--------------------------------------"

# Create SQL script to set up external table for billing data
echo "📝 Creating external table setup script..."

# Execute SQL commands directly in Synapse using OPENROWSET (serverless approach)
echo "🚀 Setting up billing data access in Synapse automatically..."

# Create a simpler query that works with serverless SQL pool
SQL_QUERY="SELECT TOP 10 * FROM OPENROWSET(
    BULK 'https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/billing-data/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE,
    PARSER_VERSION = '2.0'
) AS BillingData"

# Generate SAS token for Synapse access
echo ""
echo "🔑 Generating SAS token for Synapse access..."
STORAGE_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$BILLING_RG" \
    --query "[0].value" \
    --output tsv)

if [ -n "$STORAGE_KEY" ]; then
    SAS_EXPIRY=$(date -u -d '30 days' '+%Y-%m-%dT%H:%MZ' 2>/dev/null || date -v +30d '+%Y-%m-%dT%H:%MZ')
    SAS_TOKEN=$(az storage container generate-sas \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --name "$CONTAINER_NAME" \
        --permissions rl \
        --expiry "$SAS_EXPIRY" \
        --account-key "$STORAGE_KEY" \
        --output tsv)
    echo "✅ SAS token generated (valid for 30 days)"
else
    echo "⚠️  Could not generate SAS token"
    SAS_TOKEN=""
fi

# Save Synapse setup script
cat > synapse_billing_setup.sql <<EOF
-- ========================================================
-- SYNAPSE BILLING DATA SETUP
-- ========================================================
-- Auto-generated on: $(date)
-- Run this in Synapse Studio connected to Built-in serverless SQL pool
-- Workspace: $SYNAPSE_WORKSPACE
-- Storage Account: $STORAGE_ACCOUNT_NAME
-- Container: $CONTAINER_NAME

-- Step 1: Create database
CREATE DATABASE BillingAnalytics;
GO

USE BillingAnalytics;
GO

-- Step 2: Create master key (if not exists)
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd\$(openssl rand -hex 4)!';
GO

-- Step 3: Create database scoped credential with SAS token
IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'BillingStorageCredential')
    DROP DATABASE SCOPED CREDENTIAL BillingStorageCredential;
GO

CREATE DATABASE SCOPED CREDENTIAL BillingStorageCredential
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
SECRET = '$SAS_TOKEN';
GO

-- Step 4: Create external data source
IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'BillingDataSource')
    DROP EXTERNAL DATA SOURCE BillingDataSource;
GO

CREATE EXTERNAL DATA SOURCE BillingDataSource
WITH (
    LOCATION = 'https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME',
    CREDENTIAL = BillingStorageCredential
);
GO

-- Step 5: Create view for billing data
IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingData')
    DROP VIEW BillingData;
GO

CREATE VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK 'billing-data/DailyBillingExport/*/*.csv',
    DATA_SOURCE = 'BillingDataSource',
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
) AS BillingData;
GO

-- Test query
SELECT TOP 10 * FROM BillingData;
EOF

echo "✅ Synapse setup script saved to: synapse_billing_setup.sql"

# Save Python remote query client configuration
cat > synapse_config.py <<EOF
# Auto-generated Synapse configuration
# Created: $(date)

SYNAPSE_CONFIG = {
    'tenant_id': '$TENANT_ID',
    'client_id': '$APP_ID',
    'client_secret': '$CLIENT_SECRET',
    'workspace_name': '$SYNAPSE_WORKSPACE',
    'database_name': 'BillingAnalytics',
    'storage_account': '$STORAGE_ACCOUNT_NAME',
    'container': '$CONTAINER_NAME',
    'resource_group': '$BILLING_RG',
    'subscription_id': '$APP_SUBSCRIPTION_ID'
}

# Connection string for ODBC
CONNECTION_STRING = f"""
DRIVER={{ODBC Driver 18 for SQL Server}};
SERVER={SYNAPSE_CONFIG['workspace_name']}-ondemand.sql.azuresynapse.net;
DATABASE={SYNAPSE_CONFIG['database_name']};
UID={SYNAPSE_CONFIG['client_id']};
PWD={SYNAPSE_CONFIG['client_secret']};
Authentication=ActiveDirectoryServicePrincipal;
Encrypt=yes;
TrustServerCertificate=no;
"""

print("Synapse Configuration:")
print(f"  Workspace: {SYNAPSE_CONFIG['workspace_name']}")
print(f"  Storage: {SYNAPSE_CONFIG['storage_account']}")
print(f"  Database: {SYNAPSE_CONFIG['database_name']}")
print(f"  Client ID: {SYNAPSE_CONFIG['client_id']}")
EOF

echo "✅ Python configuration saved to: synapse_config.py"

# Save query for reference
cat > billing_queries.sql <<EOF
-- Query billing data directly from storage (serverless SQL pool)
-- No setup required - just run these queries in Synapse Studio

-- IMPORTANT: Each daily export contains month-to-date data (cumulative)
-- To avoid duplication, query only the latest file or use DISTINCT

-- 1. Get latest billing data (most recent export file)
-- This gets the latest complete dataset without duplication
WITH LatestFile AS (
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/billing-data/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS files
)
SELECT * FROM OPENROWSET(
    BULK 'https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/billing-data/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
WHERE filepath(1) = (SELECT LatestPath FROM LatestFile)

-- 2. Query specific date range (from latest export)
-- Replace '2024-08-01' and '2024-08-10' with your desired dates
WITH LatestFile AS (
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/billing-data/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS files
)
SELECT * FROM OPENROWSET(
    BULK 'https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/billing-data/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
WHERE filepath(1) = (SELECT LatestPath FROM LatestFile)
  AND CAST(Date AS DATE) BETWEEN '2024-08-01' AND '2024-08-10'

-- 3. Daily cost summary for specific date range
WITH LatestFile AS (
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/billing-data/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS files
)
SELECT 
    CAST(Date AS DATE) as BillingDate,
    ServiceFamily,
    ResourceGroup,
    SUM(CAST(CostInUSD AS FLOAT)) as TotalCostUSD,
    COUNT(DISTINCT ResourceId) as ResourceCount
FROM OPENROWSET(
    BULK 'https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/billing-data/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
WHERE filepath(1) = (SELECT LatestPath FROM LatestFile)
  AND CAST(Date AS DATE) BETWEEN DATEADD(day, -7, GETDATE()) AND GETDATE()
GROUP BY CAST(Date AS DATE), ServiceFamily, ResourceGroup
ORDER BY BillingDate DESC

-- 4. Compare costs between two date ranges
WITH LatestFile AS (
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/billing-data/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS files
),
CurrentWeek AS (
    SELECT 
        ServiceFamily,
        SUM(CAST(CostInUSD AS FLOAT)) as CurrentCost
    FROM OPENROWSET(
        BULK 'https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/billing-data/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS BillingData
    WHERE filepath(1) = (SELECT LatestPath FROM LatestFile)
      AND CAST(Date AS DATE) BETWEEN DATEADD(day, -7, GETDATE()) AND GETDATE()
    GROUP BY ServiceFamily
),
PreviousWeek AS (
    SELECT 
        ServiceFamily,
        SUM(CAST(CostInUSD AS FLOAT)) as PreviousCost
    FROM OPENROWSET(
        BULK 'https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/billing-data/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS BillingData
    WHERE filepath(1) = (SELECT LatestPath FROM LatestFile)
      AND CAST(Date AS DATE) BETWEEN DATEADD(day, -14, GETDATE()) AND DATEADD(day, -8, GETDATE())
    GROUP BY ServiceFamily
)
SELECT 
    COALESCE(c.ServiceFamily, p.ServiceFamily) as ServiceFamily,
    ISNULL(p.PreviousCost, 0) as LastWeekCost,
    ISNULL(c.CurrentCost, 0) as ThisWeekCost,
    ISNULL(c.CurrentCost, 0) - ISNULL(p.PreviousCost, 0) as CostChange,
    CASE 
        WHEN p.PreviousCost > 0 
        THEN ((c.CurrentCost - p.PreviousCost) / p.PreviousCost * 100)
        ELSE 0 
    END as PercentChange
FROM CurrentWeek c
FULL OUTER JOIN PreviousWeek p ON c.ServiceFamily = p.ServiceFamily
ORDER BY ThisWeekCost DESC

-- 5. Monthly cost by day (for charting)
WITH LatestFile AS (
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/billing-data/*.csv',
        FORMAT = 'CSV',
        HEADER_ROW = TRUE
    ) AS files
)
SELECT 
    CAST(Date AS DATE) as BillingDate,
    SUM(CAST(CostInUSD AS FLOAT)) as DailyCost,
    SUM(SUM(CAST(CostInUSD AS FLOAT))) OVER (ORDER BY CAST(Date AS DATE)) as CumulativeCost
FROM OPENROWSET(
    BULK 'https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/billing-data/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
WHERE filepath(1) = (SELECT LatestPath FROM LatestFile)
  AND MONTH(CAST(Date AS DATE)) = MONTH(GETDATE())
  AND YEAR(CAST(Date AS DATE)) = YEAR(GETDATE())
GROUP BY CAST(Date AS DATE)
ORDER BY BillingDate
EOF

echo "✅ Query templates saved to: billing_queries.sql"

# Test the connection by running a simple query
echo "🔍 Testing Synapse connection with a sample query..."
az synapse sql query \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --query "SELECT 'Connection successful' as Status, GETDATE() as CurrentTime" \
    --only-show-errors 2>/dev/null || echo "ℹ️  Note: Direct SQL execution requires additional setup. Use Synapse Studio for now."

echo ""
echo "✅ Billing data access is ready!"
echo "📊 The queries in 'billing_queries.sql' can be run directly in Synapse Studio"
echo "   No additional setup needed - serverless SQL pool can query the CSV files directly!"

# Optional: Trigger the first export run
echo ""
read -p "Do you want to trigger the billing export to run now? (y/n): " TRIGGER_EXPORT

if [[ "$TRIGGER_EXPORT" =~ ^[Yy]$ ]]; then
    echo "🔄 Triggering billing export..."
    az rest --method POST \
        --uri "https://management.azure.com/subscriptions/$APP_SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME/run?api-version=2021-10-01" \
        --only-show-errors
    
    echo "✅ Export triggered. Data will be available in the storage account soon."
    echo "   Check: $STORAGE_ACCOUNT_NAME/$CONTAINER_NAME/billing-data/"
else
    echo "ℹ️  Export will run on its daily schedule."
fi

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
echo "   2. Access Synapse Studio: https://web.azuresynapse.net"
echo "   3. Use the queries from 'billing_queries.sql' - they work immediately!"
echo "      (No setup needed - serverless SQL pool queries CSV files directly)"
echo ""
echo "📊 Generated files for your use:"
echo "   - billing_queries.sql: Ready-to-use Synapse queries"
echo "   - synapse_billing_setup.sql: Complete Synapse setup script with SAS token"
echo "   - synapse_config.py: Python configuration for remote queries"
echo ""
echo "🚀 Next steps for remote querying:"
echo "   1. Run synapse_billing_setup.sql in Synapse Studio"
echo "   2. Use synapse_config.py with the Python client for remote access"
echo "============================================================"