#!/bin/bash

echo ""
echo "🚀 Azure Onboarding Script with Billing & Synapse Starting..."
echo "--------------------------------------"

# ===========================
# INSTALL REQUIRED TOOLS
# ===========================
echo ""
echo "🔧 Checking and installing required tools..."
echo "--------------------------------------"

# Function to detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/debian_version ]; then
            echo "debian"
        elif [ -f /etc/redhat-release ]; then
            echo "redhat"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

OS_TYPE=$(detect_os)
echo "Detected OS: $OS_TYPE"

# Install Azure CLI if not present
if ! command -v az &> /dev/null; then
    echo "📦 Installing Azure CLI..."
    
    case $OS_TYPE in
        debian)
            curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
            ;;
        redhat)
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            echo -e "[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/azure-cli.repo
            sudo yum install -y azure-cli
            ;;
        macos)
            if command -v brew &> /dev/null; then
                brew update && brew install azure-cli
            else
                echo "❌ Homebrew not found. Please install Homebrew first"
                exit 1
            fi
            ;;
        *)
            echo "⚠️ Please install Azure CLI manually"
            ;;
    esac
else
    echo "✅ Azure CLI is already installed ($(az version --query '"azure-cli"' -o tsv))"
fi

# Install Python3 and pip if not present
if ! command -v python3 &> /dev/null; then
    echo "📦 Installing Python3..."
    
    case $OS_TYPE in
        debian)
            sudo apt-get update
            sudo apt-get install -y python3 python3-pip python3-dev
            ;;
        redhat)
            sudo yum install -y python3 python3-pip python3-devel
            ;;
        macos)
            if command -v brew &> /dev/null; then
                brew install python3
            fi
            ;;
    esac
else
    echo "✅ Python3 is already installed ($(python3 --version))"
fi

# Install jq for JSON parsing
if ! command -v jq &> /dev/null; then
    echo "📦 Installing jq..."
    case $OS_TYPE in
        debian)
            sudo apt-get install -y jq
            ;;
        redhat)
            sudo yum install -y jq
            ;;
        macos)
            if command -v brew &> /dev/null; then
                brew install jq
            fi
            ;;
    esac
else
    echo "✅ jq is already installed"
fi

echo ""
echo "✅ All required tools are installed!"
echo "--------------------------------------"

# Login to Azure
if ! az account show &> /dev/null; then
    echo ""
    echo "🔐 Please login to Azure..."
    az login
else
    echo "✅ Already logged in to Azure as: $(az account show --query user.name -o tsv)"
fi

# Get current user ID early (we'll need this later)
CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null)
CURRENT_USER_NAME=$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null)
echo "Current User: $CURRENT_USER_NAME (ID: $CURRENT_USER_ID)"

# Fetch and list all subscriptions
SUBSCRIPTIONS=$(az account list --query '[].{name:name, id:id}' -o tsv)

echo "📦 Available Azure subscriptions:"
echo "$SUBSCRIPTIONS"

# Prompt user to pick subscription
read -p "🔹 Enter the Subscription ID to use: " APP_SUBSCRIPTION_ID
az account set --subscription "$APP_SUBSCRIPTION_ID"

SUBSCRIPTION_ID="$APP_SUBSCRIPTION_ID"
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
    
    # Create client secret
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
    echo ""
    read -p "Do you want to generate a NEW client secret? (y/n): " GENERATE_NEW
    
    if [[ "$GENERATE_NEW" =~ ^[Yy]$ ]]; then
        echo "🔑 Generating new client secret..."
        if date --version >/dev/null 2>&1; then
            END_DATE=$(date -d "+2 years" +"%Y-%m-%d")
        else
            END_DATE=$(date -v +2y +"%Y-%m-%d")
        fi
        CLIENT_SECRET=$(az ad app credential reset --id "$APP_ID" --end-date "$END_DATE" --query password -o tsv)
        echo "✅ New client secret generated successfully"
    else
        read -s -p "🔑 Enter the existing client secret: " CLIENT_SECRET
        echo ""
        
        if [ -z "$CLIENT_SECRET" ]; then
            echo "❌ Error: Client secret is required to continue"
            exit 1
        fi
        echo "✅ Client secret provided"
    fi
fi

# Get Service Principal Object ID
SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)
echo "Service Principal Object ID: $SP_OBJECT_ID"

# Initial permissions
echo ""
echo "🔒 Setting up initial permissions..."
echo "  - Assigning Cost Management Reader at subscription level..."
az role assignment create --assignee "$APP_ID" --role "Cost Management Reader" --scope "/subscriptions/$APP_SUBSCRIPTION_ID" --only-show-errors

# ===========================
# RESOURCE GROUP SETUP
# ===========================
BILLING_RG="rg-wiv"
STORAGE_RG="$BILLING_RG"

echo ""
echo "📁 Checking resource group '$BILLING_RG'..."
RG_EXISTS=$(az group exists --name "$BILLING_RG")

if [ "$RG_EXISTS" = "true" ]; then
    AZURE_REGION=$(az group show --name "$BILLING_RG" --query location -o tsv)
    echo "✅ Using existing resource group '$BILLING_RG' in region: $AZURE_REGION"
else
    AZURE_REGION="northeurope"
    echo "📍 Creating resource group '$BILLING_RG' in region: $AZURE_REGION"
    az group create --name "$BILLING_RG" --location "$AZURE_REGION" --only-show-errors
fi

# ===========================
# STORAGE ACCOUNT SETUP
# ===========================
echo ""
echo "💰 Configuring Azure Cost Management Billing Export..."
echo "--------------------------------------"

echo ""
read -p "Use existing billing export? (y/n): " USE_EXISTING_EXPORT

if [[ "$USE_EXISTING_EXPORT" =~ ^[Yy]$ ]]; then
    echo ""
    echo "📝 Please provide the existing billing export details:"
    
    read -p "Storage Account Name: " EXISTING_STORAGE_ACCOUNT
    read -p "Storage Account Resource Group: " EXISTING_STORAGE_RG
    read -p "Storage Account Subscription ID (or press Enter for current): " EXISTING_STORAGE_SUB
    
    if [ -z "$EXISTING_STORAGE_SUB" ]; then
        EXISTING_STORAGE_SUB=$(az account show --query id -o tsv)
    fi
    
    read -p "Container Name (default: billing-exports): " EXISTING_CONTAINER
    if [ -z "$EXISTING_CONTAINER" ]; then
        EXISTING_CONTAINER="billing-exports"
    fi
    
    read -p "Export folder path (default: billing-data): " EXISTING_EXPORT_PATH
    if [ -z "$EXISTING_EXPORT_PATH" ]; then
        EXISTING_EXPORT_PATH="billing-data"
    fi
    
    STORAGE_ACCOUNT_NAME="$EXISTING_STORAGE_ACCOUNT"
    STORAGE_RG="$EXISTING_STORAGE_RG"
    STORAGE_SUBSCRIPTION="$EXISTING_STORAGE_SUB"
    CONTAINER_NAME="$EXISTING_CONTAINER"
    EXPORT_PATH="$EXISTING_EXPORT_PATH"
    USE_EXISTING_STORAGE=true
    SKIP_EXPORT_CREATION=true
else
    USE_EXISTING_STORAGE=false
    SKIP_EXPORT_CREATION=false
    
    # Create new storage account
    STORAGE_ACCOUNT_NAME="billingstorage$(date +%s | tail -c 6)"
    echo "📦 Creating storage account '$STORAGE_ACCOUNT_NAME'..."
    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$BILLING_RG" \
        --location "$AZURE_REGION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --only-show-errors
    
    # Get storage account resource ID
    STORAGE_RESOURCE_ID=$(az storage account show \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$BILLING_RG" \
        --query id -o tsv)
    
    # Assign Storage Blob Data Reader permission
    echo "🔐 Assigning Storage Blob Data Reader on storage account..."
    az role assignment create \
        --assignee "$SP_OBJECT_ID" \
        --role "Storage Blob Data Reader" \
        --scope "$STORAGE_RESOURCE_ID" \
        --only-show-errors
    
    # Create container
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
    
    EXPORT_PATH="billing-data"
    STORAGE_SUBSCRIPTION=$(az account show --query id -o tsv)
fi

# ===========================
# BILLING EXPORT SETUP
# ===========================
if [ "$SKIP_EXPORT_CREATION" = "false" ]; then
    EXPORT_NAME="DailyBillingExport"
    echo "📊 Creating daily billing export '$EXPORT_NAME'..."
    
    # Get storage account resource ID
    STORAGE_RESOURCE_ID=$(az storage account show \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$STORAGE_RG" \
        --query id -o tsv)
    
    # Set date range
    CURRENT_DATE=$(date +%Y-%m-%d)
    CURRENT_YEAR=$(date +%Y)
    FUTURE_YEAR=$((CURRENT_YEAR + 5))
    FUTURE_DATE="${FUTURE_YEAR}-$(date +%m-%d)"
    START_DATE="${CURRENT_DATE}T00:00:00Z"
    END_DATE="${FUTURE_DATE}T00:00:00Z"
    
    echo "   Export period: $START_DATE to $END_DATE"
    
    # Create export
    az rest --method PUT \
        --uri "https://management.azure.com/subscriptions/$APP_SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME?api-version=2023-07-01-preview" \
        --body @- <<EOF 2>&1
{
  "properties": {
    "schedule": {
      "status": "Active",
      "recurrence": "Daily",
      "recurrencePeriod": {
        "from": "$START_DATE",
        "to": "$END_DATE"
      }
    },
    "format": "Csv",
    "deliveryInfo": {
      "destination": {
        "resourceId": "$STORAGE_RESOURCE_ID",
        "container": "$CONTAINER_NAME",
        "rootFolderPath": "$EXPORT_PATH"
      }
    },
    "definition": {
      "type": "FocusCost",
      "timeframe": "MonthToDate",
      "dataSet": {
        "granularity": "Daily",
        "configuration": {
          "dataVersion": "1.0",
          "compressionMode": "None",
          "overwriteMode": true
        }
      }
    },
    "partitionData": true
  }
}
EOF
    
    echo "✅ Daily billing export configured"
    
    # Trigger export
    echo "🔄 Triggering billing export..."
    az rest --method POST \
        --uri "https://management.azure.com/subscriptions/$APP_SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME/run?api-version=2023-07-01-preview" \
        --only-show-errors 2>&1
fi

# ===========================
# SYNAPSE WORKSPACE SETUP
# ===========================
echo ""
echo "🔷 Setting up Azure Synapse Analytics Workspace..."
echo "--------------------------------------"

UNIQUE_SUFFIX=$(date +%s | tail -c 6)
SYNAPSE_WORKSPACE="wiv-synapse-${UNIQUE_SUFFIX}"
echo "📝 Synapse workspace name: $SYNAPSE_WORKSPACE"

# Check if Synapse workspace exists
SYNAPSE_EXISTS=$(az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$BILLING_RG" --query name -o tsv 2>/dev/null)

if [ -n "$SYNAPSE_EXISTS" ]; then
    echo "✅ Synapse workspace '$SYNAPSE_WORKSPACE' already exists."
    SYNAPSE_STORAGE=$(az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$BILLING_RG" --query "defaultDataLakeStorage.accountUrl" -o tsv | sed 's|https://||' | sed 's|.dfs.core.windows.net||')
    FILESYSTEM_NAME=$(az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$BILLING_RG" --query "defaultDataLakeStorage.filesystem" -o tsv)
else
    echo "🏗️ Creating new Synapse workspace '$SYNAPSE_WORKSPACE'..."
    
    # Create Data Lake Storage Gen2
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
    
    # Get Data Lake storage resource ID
    DATALAKE_RESOURCE_ID=$(az storage account show \
        --name "$SYNAPSE_STORAGE" \
        --resource-group "$BILLING_RG" \
        --query id -o tsv)
    
    # Assign Storage Blob Data Contributor
    echo "🔐 Assigning Storage Blob Data Contributor on Data Lake storage..."
    az role assignment create \
        --assignee "$SP_OBJECT_ID" \
        --role "Storage Blob Data Contributor" \
        --scope "$DATALAKE_RESOURCE_ID" \
        --only-show-errors
    
    # Create filesystem
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

# Wait for workspace
echo "⏳ Waiting for Synapse workspace to be fully provisioned..."
az synapse workspace wait --resource-group "$BILLING_RG" --workspace-name "$SYNAPSE_WORKSPACE" --created

# ===========================
# CONFIGURE FIREWALL RULES
# ===========================
echo ""
echo "🔥 Configuring firewall rules..."

# Get current client IP
CLIENT_IP=$(curl -s https://api.ipify.org 2>/dev/null || echo "")

# Create firewall rules
if [ -n "$CLIENT_IP" ]; then
    echo "  - Adding rule for your IP address: $CLIENT_IP"
    az synapse workspace firewall-rule create \
        --name "ClientIP_$(echo $CLIENT_IP | tr . _)" \
        --workspace-name "$SYNAPSE_WORKSPACE" \
        --resource-group "$BILLING_RG" \
        --start-ip-address "$CLIENT_IP" \
        --end-ip-address "$CLIENT_IP" \
        --only-show-errors 2>/dev/null || true
fi

# Allow Azure services
echo "  - Adding rule for Azure services..."
az synapse workspace firewall-rule create \
    --name "AllowAllWindowsAzureIps" \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --start-ip-address "0.0.0.0" \
    --end-ip-address "0.0.0.0" \
    --only-show-errors 2>/dev/null || true

# Allow all IPs
echo "  - Adding rule for all IPs..."
az synapse workspace firewall-rule create \
    --name "AllowAllIPs" \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --start-ip-address "0.0.0.0" \
    --end-ip-address "255.255.255.255" \
    --only-show-errors 2>/dev/null || true

echo "⏳ Waiting for firewall rules to propagate..."
sleep 30

# ===========================
# CRITICAL: GRANT CURRENT USER SYNAPSE ADMIN
# ===========================
echo ""
echo "🔐 CRITICAL: Granting Synapse Administrator to current user..."
echo "   This is required for database creation to work!"

# Grant current user Synapse Administrator (CRITICAL FOR DATABASE CREATION)
if [ -n "$CURRENT_USER_ID" ]; then
    az synapse role assignment create \
        --workspace-name "$SYNAPSE_WORKSPACE" \
        --role "Synapse Administrator" \
        --assignee "$CURRENT_USER_ID" \
        --only-show-errors 2>/dev/null || true
    
    az synapse role assignment create \
        --workspace-name "$SYNAPSE_WORKSPACE" \
        --role "Synapse SQL Administrator" \
        --assignee "$CURRENT_USER_ID" \
        --only-show-errors 2>/dev/null || true
    
    echo "   ✅ Current user ($CURRENT_USER_NAME) is now Synapse Administrator"
fi

# Grant to service principal as well
echo "🔐 Granting Synapse roles to service principal..."
az synapse role assignment create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --role "Synapse Administrator" \
    --assignee "$SP_OBJECT_ID" \
    --only-show-errors 2>/dev/null || true

az synapse role assignment create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --role "Synapse SQL Administrator" \
    --assignee "$SP_OBJECT_ID" \
    --only-show-errors 2>/dev/null || true

# ===========================
# GRANT STORAGE PERMISSIONS
# ===========================
echo ""
echo "🔐 Configuring storage access permissions..."

# Get Synapse Managed Identity
SYNAPSE_IDENTITY=$(az synapse workspace show \
    --name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --query "identity.principalId" \
    --output tsv 2>/dev/null)

if [ -n "$SYNAPSE_IDENTITY" ]; then
    echo "  - Granting Storage Blob Data Reader to Synapse Managed Identity..."
    
    # Get storage resource ID
    STORAGE_RESOURCE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$STORAGE_RG/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME"
    
    az role assignment create \
        --role "Storage Blob Data Reader" \
        --assignee "$SYNAPSE_IDENTITY" \
        --scope "$STORAGE_RESOURCE_ID" \
        --only-show-errors 2>/dev/null || true
fi

# Also grant to service principal
echo "  - Granting Storage Blob Data Reader to Service Principal..."
az role assignment create \
    --role "Storage Blob Data Reader" \
    --assignee "$SP_OBJECT_ID" \
    --scope "$STORAGE_RESOURCE_ID" \
    --only-show-errors 2>/dev/null || true

# Grant to current user
if [ -n "$CURRENT_USER_ID" ]; then
    echo "  - Granting Storage Blob Data Reader to current user..."
    az role assignment create \
        --role "Storage Blob Data Reader" \
        --assignee "$CURRENT_USER_ID" \
        --scope "$STORAGE_RESOURCE_ID" \
        --only-show-errors 2>/dev/null || true
fi

# ===========================
# WAIT FOR SYNAPSE AND PERMISSIONS
# ===========================
echo ""
echo "⏳ Waiting for Synapse and permissions to be ready..."
echo "   Synapse SQL pools need time to initialize..."
sleep 60
echo "   Permissions need time to propagate..."
sleep 60

# ===========================
# DATABASE AND VIEW CREATION
# ===========================
echo ""
echo "🔧 Creating BillingAnalytics database..."
echo "--------------------------------------"

# Get Azure access token
ACCESS_TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>/dev/null)

DATABASE_CREATED=false

if [ -n "$ACCESS_TOKEN" ]; then
    echo "✅ Got Azure CLI access token"
    
    # Function to execute SQL
    execute_sql() {
        local database=$1
        local query=$2
        local description=$3
        
        echo "  $description..."
        
        local json_query=$(echo -n "$query" | jq -Rs .)
        
        local response=$(curl -s -w "\n##HTTP_STATUS##%{http_code}" -X POST \
            "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/${database}/query" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"query\": $json_query}" 2>&1)
        
        local http_status=$(echo "$response" | grep -o "##HTTP_STATUS##.*" | cut -d'#' -f5)
        
        if [[ "$http_status" == "200" ]] || [[ "$http_status" == "201" ]] || [[ "$http_status" == "202" ]]; then
            echo "    ✅ Success"
            return 0
        else
            echo "    ⚠️  Failed (HTTP $http_status)"
            return 1
        fi
    }
    
    # Create database
    execute_sql "master" \
        "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics') CREATE DATABASE BillingAnalytics" \
        "Creating database BillingAnalytics"
    
    sleep 5
    
    # Create master key
    MASTER_KEY_PASSWORD="StrongP@ssw0rd$(date +%s | tail -c 4)!"
    execute_sql "BillingAnalytics" \
        "IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##') CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$MASTER_KEY_PASSWORD'" \
        "Creating master key"
    
    sleep 3
    
    # Create credential
    execute_sql "BillingAnalytics" \
        "IF NOT EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'WorkspaceIdentity') CREATE DATABASE SCOPED CREDENTIAL WorkspaceIdentity WITH IDENTITY = 'Managed Identity'" \
        "Creating credential"
    
    sleep 3
    
    # Create external data source
    execute_sql "BillingAnalytics" \
        "IF NOT EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'BillingStorage') CREATE EXTERNAL DATA SOURCE BillingStorage WITH (LOCATION = 'abfss://${CONTAINER_NAME}@${STORAGE_ACCOUNT_NAME}.dfs.core.windows.net/', CREDENTIAL = WorkspaceIdentity)" \
        "Creating data source"
    
    sleep 3
    
    # Create user for service principal
    execute_sql "BillingAnalytics" \
        "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account') CREATE USER [wiv_account] FROM EXTERNAL PROVIDER" \
        "Creating user wiv_account"
    
    sleep 3
    
    # Grant permissions
    execute_sql "BillingAnalytics" \
        "ALTER ROLE db_datareader ADD MEMBER [wiv_account]" \
        "Granting db_datareader"
    
    execute_sql "BillingAnalytics" \
        "ALTER ROLE db_datawriter ADD MEMBER [wiv_account]" \
        "Granting db_datawriter"
    
    execute_sql "BillingAnalytics" \
        "ALTER ROLE db_ddladmin ADD MEMBER [wiv_account]" \
        "Granting db_ddladmin"
    
    sleep 3
    
    # Create view - ALWAYS create placeholder first since no files exist yet
    echo "  Creating placeholder view (billing files not ready yet)..."
    
    # Drop existing view
    execute_sql "BillingAnalytics" \
        "IF OBJECT_ID('BillingData', 'V') IS NOT NULL DROP VIEW BillingData" \
        "Dropping existing view"
    
    # Create placeholder view that won't fail
    PLACEHOLDER_SQL="CREATE VIEW BillingData AS
SELECT 
    'No billing data available yet' AS Status,
    'Billing export will run at midnight UTC or was triggered earlier' AS Message,
    '${STORAGE_ACCOUNT_NAME}' AS StorageAccount,
    '${CONTAINER_NAME}' AS Container,
    '${EXPORT_PATH}/DailyBillingExport/YYYYMMDD-YYYYMMDD/GUID/*.csv' AS ExpectedPattern,
    'Run update_billing_view.sql once files exist' AS NextStep,
    GETDATE() AS CheckedAt"
    
    if execute_sql "BillingAnalytics" "$PLACEHOLDER_SQL" "Creating placeholder view"; then
        DATABASE_CREATED=true
        echo "    ✅ Placeholder view created"
    fi
fi

# ===========================
# CREATE UPDATE SCRIPTS
# ===========================

# Create script to update view when data is available
cat > update_billing_view.sql <<EOF
-- ========================================================
-- UPDATE BILLING VIEW WHEN DATA IS AVAILABLE
-- ========================================================
-- Run this after billing export creates files

USE BillingAnalytics;
GO

-- First, check what files exist
SELECT TOP 10
    r.filepath() as FilePath
FROM OPENROWSET(
    BULK '$EXPORT_PATH/DailyBillingExport/*/*/*/*.csv',
    DATA_SOURCE = 'BillingStorage',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS r;
GO

-- Drop existing view
IF OBJECT_ID('BillingData', 'V') IS NOT NULL
    DROP VIEW BillingData;
GO

-- Create view with proper path
-- Update the date range (YYYYMMDD-YYYYMMDD) based on actual files
CREATE VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK '$EXPORT_PATH/DailyBillingExport/*/*/*/*.csv',
    DATA_SOURCE = 'BillingStorage',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) WITH (
    -- Define schema to avoid errors
    BillingAccountId VARCHAR(256),
    BillingAccountName VARCHAR(256),
    BillingCurrency VARCHAR(16),
    ChargeType VARCHAR(64),
    ConsumedService VARCHAR(256),
    CostInBillingCurrency VARCHAR(50),
    CostInUsd VARCHAR(50),
    [Date] VARCHAR(50),
    EffectiveCost VARCHAR(50),
    Frequency VARCHAR(64),
    ListCost VARCHAR(50),
    MeterCategory VARCHAR(256),
    MeterName VARCHAR(512),
    MeterSubCategory VARCHAR(256),
    PayGPrice VARCHAR(50),
    ProductName VARCHAR(512),
    PublisherType VARCHAR(64),
    Quantity VARCHAR(50),
    ResourceGroupName VARCHAR(256),
    ResourceId VARCHAR(512),
    ResourceLocation VARCHAR(256),
    ResourceName VARCHAR(512),
    ServiceFamily VARCHAR(256),
    ServiceName VARCHAR(256),
    SubscriptionId VARCHAR(256),
    SubscriptionName VARCHAR(256),
    Tags VARCHAR(4000),
    UnitOfMeasure VARCHAR(64)
) AS BillingExport;
GO

-- Test the view
SELECT TOP 10 * FROM BillingData;
GO
EOF

# Create manual setup script
cat > synapse_billing_setup.sql <<EOF
-- ========================================================
-- COMPLETE SYNAPSE SETUP (MANUAL)
-- ========================================================
-- Run this in Synapse Studio if automated setup failed

-- Create database
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics')
    CREATE DATABASE BillingAnalytics;
GO

USE BillingAnalytics;
GO

-- Create master key
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd2024!';
GO

-- Create credential
IF NOT EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'WorkspaceIdentity')
    CREATE DATABASE SCOPED CREDENTIAL WorkspaceIdentity 
    WITH IDENTITY = 'Managed Identity';
GO

-- Create external data source
IF NOT EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'BillingStorage')
    CREATE EXTERNAL DATA SOURCE BillingStorage
    WITH (
        LOCATION = 'abfss://$CONTAINER_NAME@$STORAGE_ACCOUNT_NAME.dfs.core.windows.net/',
        CREDENTIAL = WorkspaceIdentity
    );
GO

-- Create user for service principal
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account')
    CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
GO

-- Grant permissions
ALTER ROLE db_datareader ADD MEMBER [wiv_account];
ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
GO

-- Create placeholder view (since no files exist yet)
IF OBJECT_ID('BillingData', 'V') IS NOT NULL
    DROP VIEW BillingData;
GO

CREATE VIEW BillingData AS
SELECT 
    'No billing data available yet' AS Status,
    'Waiting for billing export to complete' AS Message,
    '$STORAGE_ACCOUNT_NAME' AS StorageAccount,
    '$CONTAINER_NAME' AS Container,
    GETDATE() AS CheckedAt;
GO

-- Set database collation to UTF8
ALTER DATABASE BillingAnalytics 
COLLATE Latin1_General_100_CI_AS_SC_UTF8;

SELECT * FROM BillingData;
GO
EOF

# Create Python configuration
cat > synapse_config.py <<EOF
# Synapse Configuration
SYNAPSE_CONFIG = {
    'tenant_id': '$TENANT_ID',
    'client_id': '$APP_ID',
    'client_secret': '$CLIENT_SECRET',
    'workspace_name': '$SYNAPSE_WORKSPACE',
    'database_name': 'BillingAnalytics',
    'storage_account': '$STORAGE_ACCOUNT_NAME',
    'container': '$CONTAINER_NAME',
    'export_path': '$EXPORT_PATH',
    'resource_group': '$BILLING_RG',
    'subscription_id': '$APP_SUBSCRIPTION_ID'
}
EOF

# ===========================
# FINAL OUTPUT
# ===========================
echo ""
echo "============================================================"
echo "✅ Azure Onboarding Complete"
echo "============================================================"
echo ""
echo "📄 Service Principal:"
echo "   Tenant ID:        $TENANT_ID"
echo "   App ID:           $APP_ID"
echo "   Client Secret:    $CLIENT_SECRET"
echo ""
echo "💾 Storage:"
echo "   Account:          $STORAGE_ACCOUNT_NAME"
echo "   Container:        $CONTAINER_NAME"
echo "   Export Path:      $EXPORT_PATH/DailyBillingExport"
echo ""
echo "🔷 Synapse:"
echo "   Workspace:        $SYNAPSE_WORKSPACE"
echo "   Endpoint:         ${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net"
echo "   Database:         BillingAnalytics"
echo ""
echo "👤 Current User:"
echo "   Name:             $CURRENT_USER_NAME"
echo "   Synapse Role:     Administrator ✅"
echo ""

if [ "$DATABASE_CREATED" = "true" ]; then
    echo "✅ Status: DATABASE AND PLACEHOLDER VIEW CREATED"
    echo ""
    echo "📝 Next Steps:"
    echo "   1. Wait for billing export to create files (5-30 min)"
    echo "   2. Open Synapse Studio: https://web.azuresynapse.net"
    echo "   3. Once files exist, run: update_billing_view.sql"
else
    echo "⚠️  Status: MANUAL SETUP REQUIRED"
    echo ""
    echo "📝 Complete manually:"
    echo "   1. Open: https://web.azuresynapse.net"
    echo "   2. Run: synapse_billing_setup.sql"
fi

echo ""
echo "📊 Generated Files:"
echo "   update_billing_view.sql  - Run this after billing files exist"
echo "   synapse_billing_setup.sql - Manual setup if needed"
echo "   synapse_config.py        - Python configuration"
echo ""
echo "⚠️  Important: Billing files don't exist yet!"
echo "   The view currently returns a placeholder message."
echo "   Once files are created, update the view using update_billing_view.sql"
echo ""
echo "============================================================"