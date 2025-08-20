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
        --assignee "$APP_ID" \
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
          "dataVersion": "1.0"
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
        --assignee "$APP_ID" \
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

# Grant Synapse roles
echo "🔐 Granting Synapse workspace roles..."
az synapse role assignment create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --role "Synapse Administrator" \
    --assignee "$APP_ID" \
    --only-show-errors 2>/dev/null || true

az synapse role assignment create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --role "Synapse SQL Administrator" \
    --assignee "$APP_ID" \
    --only-show-errors 2>/dev/null || true

# Get current user ID and grant admin role
CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null)
if [ -n "$CURRENT_USER_ID" ]; then
    az synapse role assignment create \
        --workspace-name "$SYNAPSE_WORKSPACE" \
        --role "Synapse Administrator" \
        --assignee "$CURRENT_USER_ID" \
        --only-show-errors 2>/dev/null || true
fi

sleep 30

# ===========================
# DATABASE AND VIEW CREATION (FIXED)
# ===========================
echo ""
echo "🔧 Creating BillingAnalytics database and configuring permissions..."
echo "--------------------------------------"

# Get Azure access token
ACCESS_TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>/dev/null)

if [ -n "$ACCESS_TOKEN" ]; then
    echo "✅ Got Azure CLI access token"
    
    # Function to execute SQL with proper error handling
    execute_sql() {
        local database=$1
        local query=$2
        local description=$3
        
        echo "  $description..."
        
        # Properly escape the query for JSON
        local json_query=$(echo -n "$query" | jq -Rs .)
        
        local response=$(curl -s -w "\n##HTTP_STATUS##%{http_code}" -X POST \
            "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/${database}/query" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"query\": $json_query}" 2>&1)
        
        local http_status=$(echo "$response" | grep -o "##HTTP_STATUS##.*" | cut -d'#' -f5)
        local body=$(echo "$response" | sed '/##HTTP_STATUS##/d')
        
        if [[ "$http_status" == "200" ]] || [[ "$http_status" == "201" ]] || [[ "$http_status" == "202" ]]; then
            echo "    ✅ Success"
            return 0
        else
            echo "    ⚠️  HTTP $http_status"
            if [[ "$body" == *"already exists"* ]]; then
                echo "    ℹ️  Already exists"
                return 0
            fi
            return 1
        fi
    }
    
    # Step 1: Create database
    execute_sql "master" \
        "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics') CREATE DATABASE BillingAnalytics" \
        "Creating database BillingAnalytics"
    
    sleep 5
    
    # Step 2: Create master key
    MASTER_KEY_PASSWORD="StrongP@ssw0rd$(date +%s | tail -c 4)!"
    execute_sql "BillingAnalytics" \
        "IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##') CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$MASTER_KEY_PASSWORD'" \
        "Creating master key"
    
    sleep 3
    
    # Step 3: Create database scoped credential for managed identity
    execute_sql "BillingAnalytics" \
        "IF NOT EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'WorkspaceIdentity') CREATE DATABASE SCOPED CREDENTIAL WorkspaceIdentity WITH IDENTITY = 'Managed Identity'" \
        "Creating database scoped credential"
    
    sleep 3
    
    # Step 4: Create external data source
    execute_sql "BillingAnalytics" \
        "IF NOT EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'BillingStorage') CREATE EXTERNAL DATA SOURCE BillingStorage WITH (LOCATION = 'abfss://${CONTAINER_NAME}@${STORAGE_ACCOUNT_NAME}.dfs.core.windows.net/', CREDENTIAL = WorkspaceIdentity)" \
        "Creating external data source"
    
    sleep 3
    
    # Step 5: Create user for service principal
    execute_sql "BillingAnalytics" \
        "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account') CREATE USER [wiv_account] FROM EXTERNAL PROVIDER" \
        "Creating user wiv_account"
    
    sleep 3
    
    # Step 6: Grant permissions
    execute_sql "BillingAnalytics" \
        "ALTER ROLE db_datareader ADD MEMBER [wiv_account]" \
        "Granting db_datareader role"
    
    execute_sql "BillingAnalytics" \
        "ALTER ROLE db_datawriter ADD MEMBER [wiv_account]" \
        "Granting db_datawriter role"
    
    execute_sql "BillingAnalytics" \
        "ALTER ROLE db_ddladmin ADD MEMBER [wiv_account]" \
        "Granting db_ddladmin role"
    
    sleep 3
    
    # Step 7: Create view for billing data
    echo "  Creating BillingData view..."
    
    # First, drop existing view if it exists
    execute_sql "BillingAnalytics" \
        "IF OBJECT_ID('BillingData', 'V') IS NOT NULL DROP VIEW BillingData" \
        "Dropping existing view"
    
    # Create the view with proper OPENROWSET
    VIEW_SQL="CREATE VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK '${EXPORT_PATH}/**/*.csv',
    DATA_SOURCE = 'BillingStorage',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport"
    
    execute_sql "BillingAnalytics" "$VIEW_SQL" "Creating BillingData view"
    
    echo ""
    echo "✅ Database setup completed successfully!"
    DATABASE_CREATED=true
    
else
    echo "❌ Failed to get access token"
    DATABASE_CREATED=false
fi

# ===========================
# CREATE MANUAL SETUP SCRIPTS
# ===========================

# Create manual SQL script
cat > synapse_billing_setup.sql <<EOF
-- ========================================================
-- SYNAPSE BILLING DATA SETUP (Manual)
-- ========================================================
-- Run this in Synapse Studio if automated setup fails
-- Workspace: $SYNAPSE_WORKSPACE
-- Storage Account: $STORAGE_ACCOUNT_NAME
-- Container: $CONTAINER_NAME
-- Export Path: $EXPORT_PATH

-- Step 1: Create database
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics')
    CREATE DATABASE BillingAnalytics;
GO

USE BillingAnalytics;
GO

-- Step 2: Create master key
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd2024!';
GO

-- Step 3: Create database scoped credential for managed identity
IF NOT EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'WorkspaceIdentity')
    CREATE DATABASE SCOPED CREDENTIAL WorkspaceIdentity 
    WITH IDENTITY = 'Managed Identity';
GO

-- Step 4: Create external data source
IF NOT EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'BillingStorage')
    CREATE EXTERNAL DATA SOURCE BillingStorage
    WITH (
        LOCATION = 'abfss://$CONTAINER_NAME@$STORAGE_ACCOUNT_NAME.dfs.core.windows.net/',
        CREDENTIAL = WorkspaceIdentity
    );
GO

-- Step 5: Create user for service principal
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account')
    CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
GO

-- Step 6: Grant permissions
ALTER ROLE db_datareader ADD MEMBER [wiv_account];
ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
GO

-- Step 7: Create view for billing data
IF OBJECT_ID('BillingData', 'V') IS NOT NULL
    DROP VIEW BillingData;
GO

CREATE VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK '$EXPORT_PATH/**/*.csv',
    DATA_SOURCE = 'BillingStorage',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport;
GO

-- Test the view
SELECT TOP 10 * FROM BillingData;
GO
EOF

echo "✅ Manual SQL script saved to: synapse_billing_setup.sql"

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

# Connection string for pyodbc
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
for key, value in SYNAPSE_CONFIG.items():
    if key != 'client_secret':
        print(f"  {key}: {value}")
EOF

echo "✅ Python configuration saved to: synapse_config.py"

# Create sample queries
cat > billing_queries.sql <<EOF
-- Sample Billing Queries for Synapse

-- 1. Test connection and view
SELECT TOP 10 * FROM BillingAnalytics.dbo.BillingData;

-- 2. Daily cost summary
SELECT 
    CAST(Date AS DATE) as BillingDate,
    ServiceFamily,
    ResourceGroupName,
    SUM(TRY_CAST(CostInUSD AS FLOAT)) as TotalCostUSD
FROM BillingAnalytics.dbo.BillingData
WHERE TRY_CAST(Date AS DATE) >= DATEADD(day, -7, GETDATE())
GROUP BY CAST(Date AS DATE), ServiceFamily, ResourceGroupName
ORDER BY BillingDate DESC;

-- 3. Top spending services
SELECT TOP 10
    ServiceFamily,
    SUM(TRY_CAST(CostInUSD AS FLOAT)) as TotalCost
FROM BillingAnalytics.dbo.BillingData
GROUP BY ServiceFamily
ORDER BY TotalCost DESC;
EOF

echo "✅ Sample queries saved to: billing_queries.sql"

# ===========================
# FINAL OUTPUT
# ===========================
echo ""
echo "============================================================"
echo "✅ Azure Onboarding with Billing Export and Synapse Complete"
echo "============================================================"
echo ""
echo "📄 Service Principal Credentials:"
echo "   Tenant ID:        $TENANT_ID"
echo "   App (Client) ID:  $APP_ID"
echo "   Client Secret:    $CLIENT_SECRET"
echo ""
echo "💾 Storage Configuration:"
echo "   Resource Group:   $BILLING_RG"
echo "   Storage Account:  $STORAGE_ACCOUNT_NAME"
echo "   Container:        $CONTAINER_NAME"
echo "   Export Path:      $EXPORT_PATH"
echo ""
echo "🔷 Synapse Configuration:"
echo "   Workspace:        $SYNAPSE_WORKSPACE"
echo "   SQL Endpoint:     ${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net"
if [ -n "$SQL_ADMIN_USER" ]; then
    echo "   SQL Admin User:   $SQL_ADMIN_USER"
    echo "   SQL Admin Pass:   $SQL_ADMIN_PASSWORD"
fi
echo ""

if [ "$DATABASE_CREATED" = "true" ]; then
    echo "✅ Database Status: CREATED AND CONFIGURED"
    echo ""
    echo "📝 Next Steps:"
    echo "   1. Wait 5-30 minutes for billing data to be exported"
    echo "   2. Open Synapse Studio: https://web.azuresynapse.net"
    echo "   3. Select workspace: $SYNAPSE_WORKSPACE"
    echo "   4. Run queries from: billing_queries.sql"
    echo ""
    echo "   Query example:"
    echo "   SELECT TOP 10 * FROM BillingAnalytics.dbo.BillingData"
else
    echo "⚠️  Database Status: MANUAL SETUP REQUIRED"
    echo ""
    echo "📝 Complete setup manually:"
    echo "   1. Open Synapse Studio: https://web.azuresynapse.net"
    echo "   2. Select workspace: $SYNAPSE_WORKSPACE"
    echo "   3. Go to 'Develop' → 'SQL scripts' → 'New SQL script'"
    echo "   4. Connect to: 'Built-in' serverless SQL pool"
    echo "   5. Copy and run the SQL from: synapse_billing_setup.sql"
fi

echo ""
echo "📊 Generated Files:"
echo "   - synapse_billing_setup.sql : Manual setup SQL script"
echo "   - synapse_config.py         : Python configuration"
echo "   - billing_queries.sql       : Sample queries"
echo ""
echo "============================================================"