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
# GRANT SYNAPSE PERMISSIONS
# ===========================
echo "🔐 Granting Synapse workspace roles..."

# Grant Synapse roles to service principal
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

# Get current user ID and grant admin role
CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null)
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
fi

# ===========================
# GRANT STORAGE PERMISSIONS TO SYNAPSE
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
# ENHANCED WAIT FOR SYNAPSE WITH VERIFICATION
# ===========================
echo ""
echo "⏳ Waiting for Synapse SQL pools to be fully initialized..."
echo "   This is CRITICAL - Synapse needs 5-10 minutes to be ready"
echo ""

# Function to test Synapse connectivity
test_synapse_ready() {
    local test_token=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>/dev/null)
    
    if [ -z "$test_token" ]; then
        return 1
    fi
    
    local test_response=$(curl -s -w "\n##HTTP_STATUS##%{http_code}" -X POST \
        "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/master/query" \
        -H "Authorization: Bearer $test_token" \
        -H "Content-Type: application/json" \
        -d '{"query": "SELECT 1 as test"}' 2>&1)
    
    local http_status=$(echo "$test_response" | grep -o "##HTTP_STATUS##.*" | cut -d'#' -f5)
    
    if [[ "$http_status" == "200" ]]; then
        return 0
    else
        return 1
    fi
}

# Wait loop with verification
MAX_WAIT=10
WAIT_COUNT=0

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    WAIT_COUNT=$((WAIT_COUNT + 1))
    echo "   Checking Synapse readiness (attempt $WAIT_COUNT/$MAX_WAIT)..."
    
    if test_synapse_ready; then
        echo "   ✅ Synapse is ready!"
        break
    else
        if [ $WAIT_COUNT -lt $MAX_WAIT ]; then
            echo "   Not ready yet. Waiting 60 seconds..."
            sleep 60
        else
            echo "   ⚠️  Synapse may not be fully ready. Proceeding anyway..."
        fi
    fi
done

# Additional wait for good measure
echo "   Final 30-second wait for all services..."
sleep 30

# ===========================
# DATABASE AND VIEW CREATION WITH ROBUST ERROR HANDLING
# ===========================
echo ""
echo "🔧 Creating BillingAnalytics database and configuring permissions..."
echo "--------------------------------------"

# Function to execute SQL with enhanced error handling
execute_sql_safe() {
    local database=$1
    local query=$2
    local description=$3
    local token=$4
    
    echo "  $description..."
    
    # Properly escape the query for JSON
    local json_query=$(echo -n "$query" | jq -Rs .)
    
    local response=$(curl -s -w "\n##HTTP_STATUS##%{http_code}" -X POST \
        "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/${database}/query" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{\"query\": $json_query}" 2>&1)
    
    local http_status=$(echo "$response" | grep -o "##HTTP_STATUS##.*" | cut -d'#' -f5)
    local body=$(echo "$response" | sed '/##HTTP_STATUS##/d')
    
    if [[ "$http_status" == "200" ]] || [[ "$http_status" == "201" ]] || [[ "$http_status" == "202" ]]; then
        echo "    ✅ Success"
        return 0
    elif [[ "$body" == *"already exists"* ]] || [[ "$body" == *"already a member"* ]]; then
        echo "    ℹ️  Already exists"
        return 0
    else
        echo "    ⚠️  Failed (HTTP $http_status)"
        return 1
    fi
}

# Get fresh token for database creation
ACCESS_TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>/dev/null)

DATABASE_CREATED=false

if [ -n "$ACCESS_TOKEN" ]; then
    echo "✅ Got Azure CLI access token"
    
    # Create database with retries
    echo ""
    echo "  Step 1: Creating database..."
    RETRY=0
    while [ $RETRY -lt 3 ]; do
        if execute_sql_safe "master" \
            "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics') CREATE DATABASE BillingAnalytics" \
            "Creating database (attempt $((RETRY+1)))" \
            "$ACCESS_TOKEN"; then
            break
        fi
        RETRY=$((RETRY+1))
        [ $RETRY -lt 3 ] && sleep 10
    done
    
    sleep 5
    
    # Create master key
    echo "  Step 2: Creating master key..."
    MASTER_KEY_PASSWORD="StrongP@ssw0rd$(date +%s | tail -c 4)!"
    execute_sql_safe "BillingAnalytics" \
        "IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##') CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$MASTER_KEY_PASSWORD'" \
        "Creating master key" \
        "$ACCESS_TOKEN"
    
    sleep 3
    
    # Create credential
    echo "  Step 3: Creating database scoped credential..."
    execute_sql_safe "BillingAnalytics" \
        "IF NOT EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'WorkspaceIdentity') CREATE DATABASE SCOPED CREDENTIAL WorkspaceIdentity WITH IDENTITY = 'Managed Identity'" \
        "Creating credential" \
        "$ACCESS_TOKEN"
    
    sleep 3
    
    # Create external data source
    echo "  Step 4: Creating external data source..."
    execute_sql_safe "BillingAnalytics" \
        "IF NOT EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'BillingStorage') CREATE EXTERNAL DATA SOURCE BillingStorage WITH (LOCATION = 'abfss://${CONTAINER_NAME}@${STORAGE_ACCOUNT_NAME}.dfs.core.windows.net/', CREDENTIAL = WorkspaceIdentity)" \
        "Creating data source" \
        "$ACCESS_TOKEN"
    
    sleep 3
    
    # Create user
    echo "  Step 5: Creating user for service principal..."
    execute_sql_safe "BillingAnalytics" \
        "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account') CREATE USER [wiv_account] FROM EXTERNAL PROVIDER" \
        "Creating user" \
        "$ACCESS_TOKEN"
    
    sleep 3
    
    # Grant permissions
    echo "  Step 6: Granting permissions..."
    execute_sql_safe "BillingAnalytics" \
        "ALTER ROLE db_datareader ADD MEMBER [wiv_account]" \
        "Granting db_datareader" \
        "$ACCESS_TOKEN"
    
    execute_sql_safe "BillingAnalytics" \
        "ALTER ROLE db_datawriter ADD MEMBER [wiv_account]" \
        "Granting db_datawriter" \
        "$ACCESS_TOKEN"
    
    execute_sql_safe "BillingAnalytics" \
        "ALTER ROLE db_ddladmin ADD MEMBER [wiv_account]" \
        "Granting db_ddladmin" \
        "$ACCESS_TOKEN"
    
    sleep 3
    
    # Create view - flexible approach
    echo "  Step 7: Creating billing data view..."
    
    # First drop any existing view
    execute_sql_safe "BillingAnalytics" \
        "IF OBJECT_ID('BillingData', 'V') IS NOT NULL DROP VIEW BillingData" \
        "Dropping existing view" \
        "$ACCESS_TOKEN"
    
    # Try to detect actual file path
    STORAGE_KEY=$(az storage account keys list \
        --resource-group "$STORAGE_RG" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --query '[0].value' -o tsv 2>/dev/null)
    
    VIEW_CREATED=false
    
    if [ -n "$STORAGE_KEY" ]; then
        # Check if files exist
        CSV_COUNT=$(az storage blob list \
            --container-name "$CONTAINER_NAME" \
            --account-name "$STORAGE_ACCOUNT_NAME" \
            --account-key "$STORAGE_KEY" \
            --prefix "$EXPORT_PATH/DailyBillingExport" \
            --query "length([?ends_with(name, '.csv')])" -o tsv 2>/dev/null || echo "0")
        
        if [ "$CSV_COUNT" -gt 0 ]; then
            echo "    Found $CSV_COUNT CSV files"
            
            # Get first file to determine path pattern
            FIRST_FILE=$(az storage blob list \
                --container-name "$CONTAINER_NAME" \
                --account-name "$STORAGE_ACCOUNT_NAME" \
                --account-key "$STORAGE_KEY" \
                --prefix "$EXPORT_PATH/DailyBillingExport" \
                --query "[?ends_with(name, '.csv')].name | [0]" -o tsv 2>/dev/null)
            
            if [[ "$FIRST_FILE" =~ ([0-9]{8}-[0-9]{8}) ]]; then
                DATE_RANGE="${BASH_REMATCH[1]}"
                echo "    Using specific date range: $DATE_RANGE"
                
                VIEW_SQL="CREATE VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK '${EXPORT_PATH}/DailyBillingExport/${DATE_RANGE}/*/*.csv',
    DATA_SOURCE = 'BillingStorage',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport"
            else
                # Use wildcard pattern
                VIEW_SQL="CREATE VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK '${EXPORT_PATH}/DailyBillingExport/*/*/*.csv',
    DATA_SOURCE = 'BillingStorage',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport"
            fi
            
            if execute_sql_safe "BillingAnalytics" "$VIEW_SQL" "Creating view with data path" "$ACCESS_TOKEN"; then
                VIEW_CREATED=true
                DATABASE_CREATED=true
            fi
        fi
    fi
    
    # If no files or view creation failed, create placeholder
    if [ "$VIEW_CREATED" = "false" ]; then
        echo "    Creating placeholder view (no data files yet)..."
        
        PLACEHOLDER_SQL="CREATE VIEW BillingData AS
SELECT 
    'No billing data available yet' AS Status,
    'Waiting for export to complete' AS Message,
    '${STORAGE_ACCOUNT_NAME}' AS StorageAccount,
    '${CONTAINER_NAME}' AS Container,
    '${EXPORT_PATH}/DailyBillingExport' AS ExpectedPath,
    GETDATE() AS CheckedAt"
        
        if execute_sql_safe "BillingAnalytics" "$PLACEHOLDER_SQL" "Creating placeholder view" "$ACCESS_TOKEN"; then
            DATABASE_CREATED=true
            echo "    ✅ Placeholder view created"
        fi
    fi
    
    if [ "$DATABASE_CREATED" = "true" ]; then
        echo ""
        echo "✅ Database setup completed!"
    fi
else
    echo "❌ Failed to get access token"
fi

# ===========================
# CREATE MANUAL SETUP SCRIPTS
# ===========================

# Create comprehensive manual SQL script
cat > synapse_billing_setup.sql <<EOF
-- ========================================================
-- COMPLETE SYNAPSE BILLING SETUP (MANUAL)
-- ========================================================
-- Run this entire script in Synapse Studio if automated setup failed
-- Connect to: Built-in serverless SQL pool

-- Configuration Values:
-- Workspace: $SYNAPSE_WORKSPACE
-- Storage: $STORAGE_ACCOUNT_NAME
-- Container: $CONTAINER_NAME
-- Path: $EXPORT_PATH

-- ========================================================
-- PART 1: DATABASE AND SECURITY SETUP
-- ========================================================

-- Create database
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics')
BEGIN
    CREATE DATABASE BillingAnalytics;
    PRINT 'Database created';
END
ELSE
BEGIN
    PRINT 'Database already exists';
END
GO

-- Switch to the database
USE BillingAnalytics;
GO

-- Create master key (required for credentials)
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd2024!';
    PRINT 'Master key created';
END
ELSE
BEGIN
    PRINT 'Master key already exists';
END
GO

-- ========================================================
-- PART 2: MANAGED IDENTITY SETUP
-- ========================================================

-- Create credential for Managed Identity
IF NOT EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'WorkspaceIdentity')
BEGIN
    CREATE DATABASE SCOPED CREDENTIAL WorkspaceIdentity 
    WITH IDENTITY = 'Managed Identity';
    PRINT 'Credential created';
END
ELSE
BEGIN
    PRINT 'Credential already exists';
END
GO

-- Create external data source
IF NOT EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'BillingStorage')
BEGIN
    CREATE EXTERNAL DATA SOURCE BillingStorage
    WITH (
        LOCATION = 'abfss://$CONTAINER_NAME@$STORAGE_ACCOUNT_NAME.dfs.core.windows.net/',
        CREDENTIAL = WorkspaceIdentity
    );
    PRINT 'External data source created';
END
ELSE
BEGIN
    PRINT 'External data source already exists';
END
GO

-- ========================================================
-- PART 3: USER AND PERMISSIONS
-- ========================================================

-- Create user for service principal
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account')
BEGIN
    CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
    PRINT 'User wiv_account created';
END
ELSE
BEGIN
    PRINT 'User already exists';
END
GO

-- Grant permissions
ALTER ROLE db_datareader ADD MEMBER [wiv_account];
ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
PRINT 'Permissions granted';
GO

-- ========================================================
-- PART 4: CREATE BILLING VIEW
-- ========================================================

-- Drop existing view
IF OBJECT_ID('BillingData', 'V') IS NOT NULL
BEGIN
    DROP VIEW BillingData;
    PRINT 'Existing view dropped';
END
GO

-- Create view for billing data
-- NOTE: You may need to adjust the path pattern based on your actual file structure
-- Common patterns:
-- Pattern 1: billing-data/DailyBillingExport/YYYYMMDD-YYYYMMDD/GUID/*.csv
-- Pattern 2: billing-data/DailyBillingExport/*/*/*.csv
-- Pattern 3: billing-data/*.csv

-- Try this first (three-level pattern):
CREATE VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK '$EXPORT_PATH/DailyBillingExport/*/*/*.csv',
    DATA_SOURCE = 'BillingStorage',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport;
GO

PRINT 'View created successfully';
GO

-- ========================================================
-- PART 5: VERIFY SETUP
-- ========================================================

-- Test the view
SELECT TOP 10 * FROM BillingData;
GO

-- If the above fails with "no files found", try these diagnostics:

-- Check what files exist (this will show the actual path structure):
/*
SELECT TOP 10
    r.filepath() as FilePath
FROM OPENROWSET(
    BULK '$EXPORT_PATH/**.csv',
    DATA_SOURCE = 'BillingStorage',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS r;
*/

-- Once you know the exact path, recreate the view with the correct pattern
EOF

echo "✅ Manual SQL script saved to: synapse_billing_setup.sql"

# Create troubleshooting script
cat > troubleshoot_synapse.sql <<EOF
-- ========================================================
-- SYNAPSE TROUBLESHOOTING QUERIES
-- ========================================================

USE BillingAnalytics;
GO

-- 1. Check database exists
SELECT name, state_desc FROM sys.databases WHERE name = 'BillingAnalytics';
GO

-- 2. Check credentials
SELECT name, credential_identity FROM sys.database_scoped_credentials;
GO

-- 3. Check external data sources
SELECT name, location FROM sys.external_data_sources;
GO

-- 4. Check users
SELECT name, type_desc, authentication_type_desc 
FROM sys.database_principals 
WHERE name = 'wiv_account';
GO

-- 5. Check permissions
SELECT 
    p.name AS principal_name,
    p.type_desc AS principal_type,
    r.name AS role_name
FROM sys.database_role_members rm
JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
JOIN sys.database_principals p ON rm.member_principal_id = p.principal_id
WHERE p.name = 'wiv_account';
GO

-- 6. Try to list files (adjust path as needed)
SELECT TOP 5
    r.filepath() as FilePath
FROM OPENROWSET(
    BULK '**.csv',
    DATA_SOURCE = 'BillingStorage',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS r;
GO
EOF

echo "✅ Troubleshooting script saved to: troubleshoot_synapse.sql"

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

if [ "$DATABASE_CREATED" = "true" ]; then
    echo "✅ Status: DATABASE CREATED SUCCESSFULLY"
    echo ""
    echo "📝 Test your setup:"
    echo "   1. Open: https://web.azuresynapse.net"
    echo "   2. Run: SELECT * FROM BillingAnalytics.dbo.BillingData"
else
    echo "⚠️  Status: MANUAL DATABASE SETUP REQUIRED"
    echo ""
    echo "📝 Complete manually:"
    echo "   1. Open: https://web.azuresynapse.net"
    echo "   2. New SQL Script → Connect to Built-in pool"
    echo "   3. Run: synapse_billing_setup.sql"
fi

echo ""
echo "📊 Generated Files:"
echo "   synapse_billing_setup.sql - Complete manual setup"
echo "   troubleshoot_synapse.sql  - Diagnostic queries"
echo "   synapse_config.py         - Python configuration"
echo ""
echo "🔐 Authentication: Managed Identity (No SAS tokens)"
echo "============================================================"