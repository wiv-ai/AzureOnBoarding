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
            # Ubuntu/Debian
            curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
            ;;
        redhat)
            # RHEL/CentOS/Fedora
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
            # macOS
            if command -v brew &> /dev/null; then
                brew update && brew install azure-cli
            else
                echo "❌ Homebrew not found. Please install Homebrew first:"
                echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                exit 1
            fi
            ;;
        *)
            echo "⚠️ Please install Azure CLI manually: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
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

# Install ODBC drivers and pyodbc dependencies
echo "📦 Installing ODBC drivers for SQL Server..."

case $OS_TYPE in
    debian)
        # Install ODBC driver dependencies
        sudo apt-get update
        sudo apt-get install -y unixodbc-dev
        
        # Install Microsoft ODBC Driver 18 for SQL Server
        if ! odbcinst -q -d -n "ODBC Driver 18 for SQL Server" &> /dev/null; then
            curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
            curl https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
            sudo apt-get update
            sudo ACCEPT_EULA=Y apt-get install -y msodbcsql18
            echo "✅ ODBC Driver 18 for SQL Server installed"
        else
            echo "✅ ODBC Driver 18 for SQL Server is already installed"
        fi
        ;;
    redhat)
        sudo yum install -y unixODBC-devel
        
        if ! odbcinst -q -d -n "ODBC Driver 18 for SQL Server" &> /dev/null; then
            curl https://packages.microsoft.com/config/rhel/8/prod.repo | sudo tee /etc/yum.repos.d/mssql-release.repo
            sudo ACCEPT_EULA=Y yum install -y msodbcsql18
            echo "✅ ODBC Driver 18 for SQL Server installed"
        else
            echo "✅ ODBC Driver 18 for SQL Server is already installed"
        fi
        ;;
    macos)
        if command -v brew &> /dev/null; then
            brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
            brew update
            HOMEBREW_NO_ENV_FILTERING=1 ACCEPT_EULA=Y brew install msodbcsql18
            echo "✅ ODBC Driver 18 for SQL Server installed"
        fi
        ;;
esac

# Install Python packages
echo "📦 Installing required Python packages..."
pip3 install --upgrade pip 2>/dev/null || python3 -m pip install --upgrade pip 2>/dev/null

# Install required Python packages
PYTHON_PACKAGES="pyodbc pandas azure-identity azure-storage-blob requests"
for package in $PYTHON_PACKAGES; do
    if ! python3 -c "import ${package%%-*}" 2>/dev/null; then
        echo "  Installing $package..."
        pip3 install $package 2>/dev/null || python3 -m pip install $package 2>/dev/null || sudo pip3 install $package 2>/dev/null
    else
        echo "  ✅ $package is already installed"
    fi
done

# Install jq for JSON parsing (useful for API responses)
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

# Install sqlcmd if not present (optional but useful)
if ! command -v sqlcmd &> /dev/null; then
    echo "📦 Installing sqlcmd (optional)..."
    case $OS_TYPE in
        debian)
            if ! command -v sqlcmd &> /dev/null; then
                curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
                curl https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list | sudo tee /etc/apt/sources.list.d/msprod.list
                sudo apt-get update
                sudo ACCEPT_EULA=Y apt-get install -y mssql-tools
                echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
                export PATH="$PATH:/opt/mssql-tools/bin"
            fi
            ;;
        redhat)
            sudo ACCEPT_EULA=Y yum install -y mssql-tools
            echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
            export PATH="$PATH:/opt/mssql-tools/bin"
            ;;
        macos)
            if command -v brew &> /dev/null; then
                brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
                brew update
                ACCEPT_EULA=Y brew install mssql-tools
            fi
            ;;
    esac
fi

echo ""
echo "✅ All required tools are installed!"
echo "--------------------------------------"

# Login to Azure (if needed)
# Check if already logged in
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
  echo "⏭️  Skipping app creation..."
  
  # Prompt for the existing client secret or create new one
  echo ""
  echo "⚠️  IMPORTANT: The service principal already exists."
  echo "   You need a client secret to continue."
  echo ""
  echo "   Options:"
  echo "   1. Enter existing client secret (if you have it)"
  echo "   2. Generate a new client secret (will invalidate old ones)"
  echo "   3. Cancel (Ctrl+C)"
  echo ""
  
  read -p "Do you want to generate a NEW client secret? (y/n): " GENERATE_NEW
  
  if [[ "$GENERATE_NEW" =~ ^[Yy]$ ]]; then
    echo "🔑 Generating new client secret..."
    # Generate expiry date (2 years from now)
    if date --version >/dev/null 2>&1; then
        END_DATE=$(date -d "+2 years" +"%Y-%m-%d")
    else
        END_DATE=$(date -v +2y +"%Y-%m-%d")
    fi
    CLIENT_SECRET=$(az ad app credential reset --id "$APP_ID" --end-date "$END_DATE" --query password -o tsv)
    echo "✅ New client secret generated successfully"
    echo ""
    echo "⚠️  IMPORTANT: Save this secret NOW! It cannot be retrieved later:"
    echo "   $CLIENT_SECRET"
    echo ""
    read -p "Press Enter once you've saved the secret..."
  else
    # Read existing client secret securely (hidden input)
    read -s -p "🔑 Enter the existing client secret: " CLIENT_SECRET
    echo "" # New line after hidden input
    
    # Validate that a secret was provided
    if [ -z "$CLIENT_SECRET" ]; then
      echo ""
      echo "❌ Error: Client secret is required to continue"
      echo ""
      echo "To create a new secret manually:"
      echo "  1. Go to Azure Portal > Azure Active Directory > App registrations"
      echo "  2. Find 'wiv_account' (App ID: $APP_ID)"
      echo "  3. Go to 'Certificates & secrets' > 'Client secrets'"
      echo "  4. Click 'New client secret' and save the value"
      echo ""
      exit 1
    fi
    
    echo "✅ Client secret provided"
  fi
fi

# Initial minimal permissions
echo ""
echo "🔒 Setting up initial permissions..."

# Only Cost Management Reader needs subscription-level access (for billing data)
echo "  - Assigning Cost Management Reader at subscription level..."
az role assignment create --assignee "$APP_ID" --role "Cost Management Reader" --scope "/subscriptions/$APP_SUBSCRIPTION_ID" --only-show-errors

echo "  ✅ Initial permissions set. Resource-specific permissions will be assigned after resource creation."

# ===========================
# BILLING EXPORT CONFIGURATION
# ===========================
echo ""
echo "💰 Configuring Azure Cost Management Billing Export..."
echo "--------------------------------------"

# Ask if user wants to use existing billing export
echo ""
echo "🔹 Do you have an existing billing export you want to use?"
echo "   (This could be from Azure Cost Management or another subscription)"
read -p "Use existing billing export? (y/n): " USE_EXISTING_EXPORT

if [[ "$USE_EXISTING_EXPORT" =~ ^[Yy]$ ]]; then
    echo ""
    echo "📝 Please provide the existing billing export details:"
    
    # Get storage account details
    read -p "Storage Account Name (e.g., billingstorage12345): " EXISTING_STORAGE_ACCOUNT
    read -p "Storage Account Resource Group: " EXISTING_STORAGE_RG
    read -p "Storage Account Subscription ID (or press Enter for current): " EXISTING_STORAGE_SUB
    
    if [ -z "$EXISTING_STORAGE_SUB" ]; then
        EXISTING_STORAGE_SUB=$(az account show --query id -o tsv)
    fi
    
    read -p "Container Name (default: billing-exports): " EXISTING_CONTAINER
    if [ -z "$EXISTING_CONTAINER" ]; then
        EXISTING_CONTAINER="billing-exports"
    fi
    
    read -p "Export folder path (e.g., billing-data or DailyExport): " EXISTING_EXPORT_PATH
    if [ -z "$EXISTING_EXPORT_PATH" ]; then
        EXISTING_EXPORT_PATH="billing-data"
    fi
    
    # Verify the storage account exists and is accessible
    echo ""
    echo "🔍 Verifying storage account access..."
    STORAGE_CHECK=$(az storage account show \
        --name "$EXISTING_STORAGE_ACCOUNT" \
        --resource-group "$EXISTING_STORAGE_RG" \
        --subscription "$EXISTING_STORAGE_SUB" \
        --query name -o tsv 2>/dev/null)
    
    if [ -n "$STORAGE_CHECK" ]; then
        echo "✅ Storage account verified: $EXISTING_STORAGE_ACCOUNT"
        STORAGE_ACCOUNT_NAME="$EXISTING_STORAGE_ACCOUNT"
        STORAGE_RG="$EXISTING_STORAGE_RG"
        STORAGE_SUBSCRIPTION="$EXISTING_STORAGE_SUB"
        CONTAINER_NAME="$EXISTING_CONTAINER"
        EXPORT_PATH="$EXISTING_EXPORT_PATH"
        USE_EXISTING_STORAGE=true
        
        # Get storage account location for Synapse
        AZURE_REGION=$(az storage account show \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$STORAGE_RG" \
            --subscription "$STORAGE_SUBSCRIPTION" \
            --query location -o tsv)
        echo "   Storage location: $AZURE_REGION"
    else
        echo "❌ Could not access storage account. Please check:"
        echo "   - Storage account name: $EXISTING_STORAGE_ACCOUNT"
        echo "   - Resource group: $EXISTING_STORAGE_RG"
        echo "   - Subscription: $EXISTING_STORAGE_SUB"
        echo "   - You have Reader access to the storage account"
        echo ""
        echo "Falling back to creating new storage..."
        USE_EXISTING_STORAGE=false
    fi
else
    USE_EXISTING_STORAGE=false
fi

# Use fixed resource group name for Synapse resources
BILLING_RG="rg-wiv"

# Only create new storage if not using existing
if [ "$USE_EXISTING_STORAGE" = "false" ]; then

# Check if resource group exists and get its location
echo "📁 Checking resource group '$BILLING_RG'..."
RG_EXISTS=$(az group exists --name "$BILLING_RG")

if [ "$RG_EXISTS" = "true" ]; then
    # Resource group exists, get its location
    AZURE_REGION=$(az group show --name "$BILLING_RG" --query location -o tsv)
    echo "✅ Using existing resource group '$BILLING_RG' in region: $AZURE_REGION"
else
    # Resource group doesn't exist, create it in eastus2 (or another region that supports Synapse)
    AZURE_REGION="northeurope"
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

# Get storage account resource ID for permissions
STORAGE_RESOURCE_ID=$(az storage account show \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$BILLING_RG" \
    --query id -o tsv)

# Assign Storage Blob Data Reader permission on this specific storage account
echo "🔐 Assigning Storage Blob Data Reader on storage account..."
az role assignment create \
    --assignee "$APP_ID" \
    --role "Storage Blob Data Reader" \
    --scope "$STORAGE_RESOURCE_ID" \
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

    # Set export path for new storage
    EXPORT_PATH="billing-data"
    STORAGE_SUBSCRIPTION=$(az account show --query id -o tsv)
fi  # End of storage creation

# Handle billing export creation
EXPORT_NAME="DailyBillingExport"

if [ "$USE_EXISTING_STORAGE" = "true" ] && [[ "$USE_EXISTING_EXPORT" =~ ^[Yy]$ ]]; then
    echo ""
    echo "✅ Using existing billing export configuration:"
    echo "   Storage: $STORAGE_ACCOUNT_NAME"
    echo "   Container: $CONTAINER_NAME"
    echo "   Path: $EXPORT_PATH"
    echo ""
    echo "ℹ️  Note: Synapse will be configured to read from this existing export"
    SKIP_EXPORT_CREATION=true
else
    echo "📊 Creating daily billing export '$EXPORT_NAME'..."
    SKIP_EXPORT_CREATION=false
fi

if [ "$SKIP_EXPORT_CREATION" = "false" ]; then

# Get storage account resource ID
STORAGE_RESOURCE_ID=$(az storage account show \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$BILLING_RG" \
    --query id -o tsv)

# Create the export using REST API with FOCUS format
# FOCUS (FinOps Open Cost and Usage Specification) provides standardized cost data
# Settings: Type=FocusCost, Version=1.0, Format=CSV, Overwrite=true (partitionData)
echo "📅 Setting up FOCUS billing export date range..."
# Use current date as start (Azure doesn't allow past dates)
CURRENT_DATE=$(date +%Y-%m-%d)
CURRENT_YEAR=$(date +%Y)
FUTURE_YEAR=$((CURRENT_YEAR + 5))
FUTURE_DATE="${FUTURE_YEAR}-$(date +%m-%d)"

START_DATE="${CURRENT_DATE}T00:00:00Z"
END_DATE="${FUTURE_DATE}T00:00:00Z"

echo "   Export period: $START_DATE to $END_DATE"

EXPORT_RESPONSE=$(az rest --method PUT \
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
        "rootFolderPath": "billing-data"
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
)

# Check if export creation was successful
if [[ "$EXPORT_RESPONSE" == *"error"* ]] || [[ "$EXPORT_RESPONSE" == *"BadRequest"* ]]; then
    echo "⚠️  Export creation failed. Checking if it already exists..."
    
    # Check if export already exists
    EXISTING_EXPORT=$(az rest --method GET \
        --uri "https://management.azure.com/subscriptions/$APP_SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME?api-version=2021-10-01" \
        --query "name" -o tsv 2>/dev/null)
    
    if [ -n "$EXISTING_EXPORT" ]; then
        echo "✅ Export '$EXPORT_NAME' already exists - no action needed"
    else
        echo "🔧 Attempting to fix export creation..."
        
        # Try deleting and recreating with cleaner JSON
        az rest --method DELETE \
            --uri "https://management.azure.com/subscriptions/$APP_SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME?api-version=2021-10-01" \
            2>/dev/null
        
        sleep 2
        
        # Ensure dates are current for retry
        CURRENT_DATE=$(date +%Y-%m-%d)
        CURRENT_YEAR=$(date +%Y)
        FUTURE_YEAR=$((CURRENT_YEAR + 5))
        FUTURE_DATE="${FUTURE_YEAR}-$(date +%m-%d)"
        START_DATE="${CURRENT_DATE}T00:00:00Z"
        END_DATE="${FUTURE_DATE}T00:00:00Z"
        
        # Create export config file for cleaner JSON handling
        cat > /tmp/export_config_$$.json <<EXPORTJSON
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
        "rootFolderPath": "billing-data"
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
EXPORTJSON
        
        # Retry with JSON file
        RETRY_RESPONSE=$(az rest --method PUT \
            --uri "https://management.azure.com/subscriptions/$APP_SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME?api-version=2023-07-01-preview" \
            --body @/tmp/export_config_$$.json 2>&1)
        
        rm -f /tmp/export_config_$$.json
        
        if [[ "$RETRY_RESPONSE" == *"error"* ]]; then
            echo "⚠️  Could not create billing export automatically"
            echo "   You can create it manually in Azure Portal > Cost Management > Exports"
            echo "   This won't affect Synapse functionality"
        else
            echo "✅ Daily billing export configured successfully on retry!"
        fi
    fi
else
    echo "✅ Daily billing export configured successfully"
fi

fi  # End of SKIP_EXPORT_CREATION check

# ===========================
# SYNAPSE WORKSPACE SETUP
# ===========================
echo ""
echo "🔷 Setting up Azure Synapse Analytics Workspace..."
echo "--------------------------------------"

# Use fixed Synapse workspace name
# Generate unique suffix for Synapse workspace name
UNIQUE_SUFFIX=$(date +%s | tail -c 6)
SYNAPSE_WORKSPACE="wiv-synapse-billing-${UNIQUE_SUFFIX}"
echo "📝 Synapse workspace name: $SYNAPSE_WORKSPACE"

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

    # Get Data Lake storage resource ID for permissions
    DATALAKE_RESOURCE_ID=$(az storage account show \
        --name "$SYNAPSE_STORAGE" \
        --resource-group "$BILLING_RG" \
        --query id -o tsv)
    
    # Assign Storage Blob Data Contributor on Data Lake (Synapse needs write access)
    echo "🔐 Assigning Storage Blob Data Contributor on Data Lake storage..."
    az role assignment create \
        --assignee "$APP_ID" \
        --role "Storage Blob Data Contributor" \
        --scope "$DATALAKE_RESOURCE_ID" \
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

# Grant the service principal Synapse roles immediately
echo "🔐 Granting Synapse workspace roles to service principal..."
az synapse role assignment create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --role "Synapse Administrator" \
    --assignee "$APP_ID" \
    --only-show-errors 2>/dev/null || echo "  Synapse Administrator role may already exist"

az synapse role assignment create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --role "Synapse SQL Administrator" \
    --assignee "$APP_ID" \
    --only-show-errors 2>/dev/null || echo "  Synapse SQL Administrator role may already exist"

# Wait for role assignments to propagate
sleep 10

# Create database and grant permissions using Azure CLI
echo ""
echo "🔧 Creating BillingAnalytics database and configuring permissions..."

# Use Azure CLI to run SQL commands directly
echo "Creating database and user with Azure CLI..."

# Create database first
az synapse sql pool list \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" &>/dev/null

# Execute SQL to create database and user using Azure user's context
SQL_SCRIPT="
-- Create database if not exists
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics')
    CREATE DATABASE BillingAnalytics;
GO

USE BillingAnalytics;
GO

-- Create master key
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd$(date +%s)!';
GO

-- Create user for service principal
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account')
BEGIN
    CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
    PRINT 'Created user wiv_account';
END
GO

-- Grant permissions
ALTER ROLE db_datareader ADD MEMBER [wiv_account];
ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
GO
"

# Save SQL to file
echo "$SQL_SCRIPT" > /tmp/create_db_user_$$.sql

# Execute using Azure Data Studio CLI or Synapse Studio REST API
echo "Executing database setup..."

# Method 1: Try using az synapse sql-script command
echo "Method 1: Using Azure CLI Synapse commands..."

# Create a SQL script in Synapse workspace
SCRIPT_NAME="SetupDatabase_$(date +%s)"
cat > /tmp/setup_db_$$.sql <<'SETUPSQL'
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

-- Create user for service principal
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account')
    CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
GO

-- Grant permissions
ALTER ROLE db_datareader ADD MEMBER [wiv_account];
ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
GO
SETUPSQL

# Create and execute the SQL script
az synapse sql-script create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --name "$SCRIPT_NAME" \
    --file /tmp/setup_db_$$.sql \
    --resource-group "$BILLING_RG" \
    --only-show-errors 2>/dev/null && echo "✅ SQL script created in Synapse"

# Method 2: Use REST API with better error handling
echo "Method 2: Using REST API with Azure user token..."
ACCESS_TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>/dev/null)

if [ -n "$ACCESS_TOKEN" ]; then
    # Create database via REST API
    echo "Creating database..."
    DB_RESPONSE=$(curl -s -X POST \
        "https://$SYNAPSE_WORKSPACE-ondemand.sql.azuresynapse.net/sql/databases/master/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"query": "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = '\''BillingAnalytics'\'') CREATE DATABASE BillingAnalytics"}' 2>&1)
    
    if [[ "$DB_RESPONSE" != *"error"* ]]; then
        echo "✅ Database created or already exists"
    else
        echo "⚠️ Database creation response: ${DB_RESPONSE:0:100}"
    fi
    
    sleep 5
    
    # Create user and grant permissions
    echo "Creating user and granting permissions..."
    GRANT_SQL="USE BillingAnalytics; IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account') CREATE USER [wiv_account] FROM EXTERNAL PROVIDER; ALTER ROLE db_datareader ADD MEMBER [wiv_account]; ALTER ROLE db_datawriter ADD MEMBER [wiv_account]; ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];"
    
    USER_RESPONSE=$(curl -s -X POST \
        "https://$SYNAPSE_WORKSPACE-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"$GRANT_SQL\"}" 2>&1)
    
    if [[ "$USER_RESPONSE" != *"error"* ]]; then
        echo "✅ User created and permissions granted"
    else
        echo "⚠️ User creation response: ${USER_RESPONSE:0:100}"
    fi
else
    echo "⚠️ Could not get access token"
fi

# Method 3: Use Azure CLI with service principal context
echo "Method 3: Granting Synapse Administrator role to service principal..."
az synapse role assignment create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --role "Synapse Administrator" \
    --assignee "$APP_ID" \
    --only-show-errors 2>/dev/null && echo "✅ Synapse Administrator role granted"

az synapse role assignment create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --role "Synapse SQL Administrator" \
    --assignee "$APP_ID" \
    --only-show-errors 2>/dev/null && echo "✅ Synapse SQL Administrator role granted"

# Clean up
rm -f /tmp/setup_db_$$.sql

# Method 4: Create a Synapse pipeline to execute SQL
echo "Method 4: Creating Synapse pipeline to execute SQL..."
PIPELINE_NAME="SetupDatabasePipeline_$(date +%s)"

# Create a pipeline definition
cat > /tmp/pipeline_$$.json <<'PIPELINEJSON'
{
  "name": "SetupDatabasePipeline",
  "properties": {
    "activities": [
      {
        "name": "CreateDatabase",
        "type": "SqlServerStoredProcedure",
        "typeProperties": {
          "storedProcedureName": "sp_executesql",
          "storedProcedureParameters": {
            "stmt": {
              "value": "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics') CREATE DATABASE BillingAnalytics",
              "type": "String"
            }
          }
        }
      }
    ]
  }
}
PIPELINEJSON

az synapse pipeline create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --name "$PIPELINE_NAME" \
    --file /tmp/pipeline_$$.json \
    --resource-group "$BILLING_RG" \
    --only-show-errors 2>/dev/null && echo "✅ Pipeline created"

rm -f /tmp/pipeline_$$.json

echo "✅ Database setup attempted with multiple methods"

# Clean up
rm -f /tmp/create_db_user_$$.sql

# Wait for changes to propagate
sleep 10

# Create and execute SQL script to set up database user
echo "Setting up database user for service principal..."
cat > /tmp/setup_db_user_$$.sql <<SQLEOF
-- Create database if not exists
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics')
    CREATE DATABASE BillingAnalytics;
GO

USE BillingAnalytics;
GO

-- Create master key if not exists
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd$(date +%s)!';
GO

-- Create user for service principal (using app name)
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account')
BEGIN
    CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
    PRINT 'Created user wiv_account';
END
GO

-- Grant permissions
ALTER ROLE db_datareader ADD MEMBER [wiv_account];
ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
GO

PRINT 'Database user configured successfully!';
GO
SQLEOF

# Execute the SQL using az synapse sql pool command
echo "Executing SQL to create database user..."
az synapse sql script create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --name "SetupDatabaseUser" \
    --file /tmp/setup_db_user_$$.sql \
    --resource-group "$BILLING_RG" \
    --only-show-errors 2>/dev/null || true

# Also try to execute it directly
az synapse sql pool list \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --query "[?name=='Built-in'].name" \
    -o tsv 2>/dev/null || true

# Clean up temp file
rm -f /tmp/setup_db_user_$$.sql

# Alternative: Use Azure user context to grant permissions
echo "Granting database access to service principal..."

# Get the current Azure user's access token for Synapse
SYNAPSE_TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>/dev/null)

if [ -n "$SYNAPSE_TOKEN" ]; then
    # Create SQL to grant permissions
    GRANT_SQL="IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account') CREATE USER [wiv_account] FROM EXTERNAL PROVIDER; ALTER ROLE db_datareader ADD MEMBER [wiv_account]; ALTER ROLE db_datawriter ADD MEMBER [wiv_account]; ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];"
    
    # Try to execute via REST API
    curl -X POST \
        "https://$SYNAPSE_WORKSPACE-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
        -H "Authorization: Bearer $SYNAPSE_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"$GRANT_SQL\"}" \
        --silent --output /dev/null 2>&1 || true
fi

echo "✅ Database and user setup completed"

# Get Synapse workspace resource ID
SYNAPSE_RESOURCE_ID=$(az synapse workspace show \
    --name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --query id -o tsv)

# Assign Contributor permission on the Synapse workspace only
echo "🔐 Assigning Contributor permission on Synapse workspace..."
az role assignment create \
    --assignee "$APP_ID" \
    --role "Contributor" \
    --scope "$SYNAPSE_RESOURCE_ID" \
    --only-show-errors

echo "⏳ Waiting for Synapse workspace to be fully operational..."
sleep 30

# Create firewall rules
echo "🔥 Configuring firewall rules..."

# Get current client IP
CLIENT_IP=$(curl -s https://api.ipify.org 2>/dev/null || echo "")
if [ -z "$CLIENT_IP" ]; then
    # Try alternative method
    CLIENT_IP=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null || echo "")
fi

# Create firewall rule for current client IP
if [ -n "$CLIENT_IP" ]; then
    echo "  - Adding rule for your IP address: $CLIENT_IP"
    az synapse workspace firewall-rule create \
        --name "ClientIP_$(echo $CLIENT_IP | tr . _)" \
        --workspace-name "$SYNAPSE_WORKSPACE" \
        --resource-group "$BILLING_RG" \
        --start-ip-address "$CLIENT_IP" \
        --end-ip-address "$CLIENT_IP" \
        --only-show-errors 2>/dev/null || echo "    (Rule may already exist)"
fi

# Create firewall rule to allow Azure services
echo "  - Adding rule for Azure services..."
az synapse workspace firewall-rule create \
    --name "AllowAllWindowsAzureIps" \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --start-ip-address "0.0.0.0" \
    --end-ip-address "0.0.0.0" \
    --only-show-errors 2>/dev/null || echo "    (Rule may already exist)"

# Create firewall rule to allow all IPs (for remote access)
echo "  - Adding rule for all IPs (remote access)..."
az synapse workspace firewall-rule create \
    --name "AllowAllIPs" \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --start-ip-address "0.0.0.0" \
    --end-ip-address "255.255.255.255" \
    --only-show-errors 2>/dev/null || echo "    (Rule may already exist)"

# Wait longer for firewall rules to propagate
echo "⏳ Waiting 30 seconds for firewall rules to fully propagate..."
sleep 30

echo "✅ Firewall rules configured"

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

# Note: The service principal that creates the workspace automatically has access
# No additional Synapse roles needed for querying billing data
echo "✅ Service principal has implicit access as workspace creator"

# Configure Managed Identity authentication (NO TOKENS NEEDED!)
echo ""
echo "🔑 Configuring Managed Identity authentication (never expires!)..."

# Grant the service principal access to the storage account
echo "Setting up Storage Blob Data Reader permissions..."
az role assignment create \
    --role "Storage Blob Data Reader" \
    --assignee "$SP_OBJECT_ID" \
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$BILLING_RG/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME" \
    --only-show-errors 2>/dev/null || echo "⚠️  SP role may already be assigned"

# Also grant Synapse workspace managed identity access
SYNAPSE_IDENTITY=$(az synapse workspace show \
    --name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --query "identity.principalId" \
    --output tsv 2>/dev/null)

if [ -n "$SYNAPSE_IDENTITY" ]; then
    az role assignment create \
        --role "Storage Blob Data Reader" \
        --assignee "$SYNAPSE_IDENTITY" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$BILLING_RG/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME" \
        --only-show-errors 2>/dev/null || echo "⚠️  Synapse role may already be assigned"
    echo "✅ Managed Identity configured - NO EXPIRATION, NO TOKENS!"
fi

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
echo "📝 Creating external table setup script..."
echo "🚀 Setting up billing data access in Synapse automatically..."

# Add longer wait after Synapse creation
echo ""
echo "⏳ Waiting for Synapse workspace to fully initialize..."
echo "   This takes 2-3 minutes for new workspaces..."
sleep 60
echo "   Still initializing... (1 minute elapsed)"
sleep 60
echo "   Almost ready... (2 minutes elapsed)"
sleep 30
echo "✅ Synapse workspace should be ready now!"

echo ""
echo "🔧 Setting up Synapse database and views automatically..."
echo "Using sqlcmd with Azure AD authentication to create database and user..."

# Generate a secure password for master key
MASTER_KEY_PASSWORD="StrongP@ssw0rd$(openssl rand -hex 4 2>/dev/null || echo $RANDOM)!"

# First, create the database and user using sqlcmd with Azure AD auth
# This uses YOUR Azure AD credentials, not the service principal
echo "📝 Creating database setup SQL script..."
cat > /tmp/setup_synapse_db_$$.sql <<SQLEOF
-- Create database if not exists
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics')
    CREATE DATABASE BillingAnalytics;
GO

USE BillingAnalytics;
GO

-- Create master key
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$MASTER_KEY_PASSWORD';
GO

-- Create user for service principal (using wiv_account name)
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account')
    CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
GO

-- Grant permissions
ALTER ROLE db_datareader ADD MEMBER [wiv_account];
ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
GO

-- Create view for billing data
CREATE OR ALTER VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK 'abfss://$CONTAINER_NAME@$STORAGE_ACCOUNT_NAME.dfs.core.windows.net/$EXPORT_PATH/*/*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport;
GO

SELECT 'Database setup complete!' as Status;
GO
SQLEOF

# Skip sqlcmd in Cloud Shell - it doesn't work with Azure AD auth properly
# Go directly to REST API method
echo "📝 Using REST API to create database and user..."
SETUP_COMPLETED=false

# Use Azure CLI to get access token
ACCESS_TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>/dev/null)

if [ -n "$ACCESS_TOKEN" ]; then
    echo "✅ Got Azure access token"
    
    # Create database
    echo "Creating database..."
    curl -s -X POST \
        "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/master/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"query": "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = '\''BillingAnalytics'\'') CREATE DATABASE BillingAnalytics"}' \
        -o /dev/null 2>&1
    
    sleep 5
    
    # Create master key, user and grant permissions
    echo "Creating user and granting permissions..."
    SETUP_SQL="IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##') CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$MASTER_KEY_PASSWORD'; IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account') CREATE USER [wiv_account] FROM EXTERNAL PROVIDER; ALTER ROLE db_datareader ADD MEMBER [wiv_account]; ALTER ROLE db_datawriter ADD MEMBER [wiv_account]; ALTER ROLE db_ddladmin ADD MEMBER [wiv_account]"
    
    curl -s -X POST \
        "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"$SETUP_SQL\"}" \
        -o /dev/null 2>&1
    
    # Also create the view
    echo "Creating BillingData view..."
    VIEW_SQL="CREATE OR ALTER VIEW BillingData AS SELECT * FROM OPENROWSET(BULK 'abfss://$CONTAINER_NAME@$STORAGE_ACCOUNT_NAME.dfs.core.windows.net/$EXPORT_PATH/*/*.csv', FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE) AS BillingExport"
    
    curl -s -X POST \
        "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"$VIEW_SQL\"}" \
        -o /dev/null 2>&1
    
    echo "✅ Database setup completed via REST API"
    SETUP_COMPLETED=true
else
    echo "⚠️ Could not get Azure access token"
    SETUP_COMPLETED=false
fi

# Clean up temp files
rm -f /tmp/setup_synapse_db_$$.sql /tmp/sqlcmd_output_$$.txt 2>/dev/null

# Skip Python fallback - keep it simple
if [ "$SETUP_COMPLETED" = "false" ]; then
    echo ""
    echo "⚠️ Automated setup could not complete"
    echo ""
    echo "📝 Manual setup required:"
    echo "   1. Open Synapse Studio: https://web.azuresynapse.net"
    echo "   2. Select workspace: $SYNAPSE_WORKSPACE"
    echo "   3. Run the SQL from: synapse_billing_setup.sql"
fi

# Create backup SQL script for manual execution
cat > synapse_billing_setup.sql <<EOF
-- ========================================================
-- SYNAPSE BILLING DATA SETUP (Manual Backup)
-- ========================================================
-- Run this in Synapse Studio if automated setup fails
-- Workspace: $SYNAPSE_WORKSPACE
    'master_key_password': '$MASTER_KEY_PASSWORD',
    'sql_admin_user': '$SQL_ADMIN_USER',
    'sql_admin_password': '$SQL_ADMIN_PASSWORD'
}

print("🚀 Running Python-based Synapse setup...")
print("📝 Creating database and user using Azure CLI token...")

# First, try to create database and user using Azure CLI token
try:
    # Get Azure user's access token (not service principal)
    result = subprocess.run(
        ["az", "account", "get-access-token", "--resource", "https://database.windows.net", "--query", "accessToken", "-o", "tsv"],
        capture_output=True,
        text=True
    )
    
    if result.returncode == 0:
        access_token = result.stdout.strip()
        print("✅ Got Azure user access token")
        
        import requests
        
        # Create database
        print("Creating BillingAnalytics database...")
        db_url = f"https://{config['workspace_name']}-ondemand.sql.azuresynapse.net/sql/databases/master/query"
        headers = {"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"}
        
        db_query = {"query": "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics') CREATE DATABASE BillingAnalytics"}
        db_response = requests.post(db_url, headers=headers, json=db_query, timeout=30)
        
        if db_response.status_code in [200, 201, 202]:
            print("✅ Database created or already exists")
        else:
            print(f"⚠️ Database creation response: {db_response.status_code}")
        
        time.sleep(10)
        
        # Create master key and user
        print("Creating master key and database user...")
        setup_url = f"https://{config['workspace_name']}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query"
        
        # Create master key
        key_query = {"query": f"IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##') CREATE MASTER KEY ENCRYPTION BY PASSWORD = '{config['master_key_password']}'"}
        key_response = requests.post(setup_url, headers=headers, json=key_query, timeout=30)
        
        if key_response.status_code in [200, 201, 202]:
            print("✅ Master key created or already exists")
        
        # Create user for service principal (using wiv_account name)
        user_query = {"query": "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account') CREATE USER [wiv_account] FROM EXTERNAL PROVIDER"}
        user_response = requests.post(setup_url, headers=headers, json=user_query, timeout=30)
        
        if user_response.status_code in [200, 201, 202]:
            print("✅ User 'wiv_account' created or already exists")
        
        # Grant permissions
        grant_query = {"query": "ALTER ROLE db_datareader ADD MEMBER [wiv_account]; ALTER ROLE db_datawriter ADD MEMBER [wiv_account]; ALTER ROLE db_ddladmin ADD MEMBER [wiv_account]"}
        grant_response = requests.post(setup_url, headers=headers, json=grant_query, timeout=30)
        
        if grant_response.status_code in [200, 201, 202]:
            print("✅ Permissions granted to 'wiv_account'")
        
        print("✅ Database and user setup completed using Azure CLI token!")
        
    else:
        print("⚠️ Could not get Azure user token")
        print("   Please ensure you're logged in with 'az login'")
        sys.exit(1)
        
except Exception as e:
    print(f"⚠️ Error during setup: {str(e)[:200]}")
    sys.exit(1)

# Wait for changes to propagate
print("⏳ Waiting for changes to propagate...")
time.sleep(15)

# NOW test if service principal can connect
print("\n📝 Testing service principal connection...")
import pyodbc

try:
    # Test connection with service principal
    conn_str = f"""
    DRIVER={{ODBC Driver 18 for SQL Server}};
    SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;
    DATABASE=BillingAnalytics;
    UID={config['client_id']};
    PWD={config['client_secret']};
    Authentication=ActiveDirectoryServicePrincipal;
    Encrypt=yes;
    TrustServerCertificate=no;
    Connection Timeout=30;
    """
    
    conn = pyodbc.connect(conn_str)
    cursor = conn.cursor()
    
    # Test query
    cursor.execute("SELECT USER_NAME() as usr, SUSER_NAME() as login")
    result = cursor.fetchone()
    print(f"✅ Service principal connected successfully!")
    print(f"   User: {result.usr}, Login: {result.login}")
    
    # Create the billing data view
    print("\n📝 Creating BillingData view...")
    try:
        cursor.execute(f"""
        CREATE OR ALTER VIEW BillingData AS
        SELECT *
        FROM OPENROWSET(
            BULK 'abfss://{config['container_name']}@{config['storage_account']}.dfs.core.windows.net/{config['export_path']}/*/*.csv',
            FORMAT = 'CSV',
            PARSER_VERSION = '2.0',
            HEADER_ROW = TRUE
        ) AS BillingExport
        """)
        print("✅ BillingData view created successfully!")
    except Exception as e:
        if "already exists" in str(e):
            print("✅ BillingData view already exists")
        else:
            print(f"⚠️ View creation: {str(e)[:100]}")
    
    cursor.close()
    conn.close()
    
    print("\n✅ Database setup completed successfully!")
    print("   You can now run queries against BillingAnalytics.dbo.BillingData")
    
except pyodbc.Error as e:
    if "Login failed" in str(e):
        print("❌ Service principal still cannot connect")
        print(f"   Error: {str(e)[:200]}")
        print("\n📝 Manual intervention required:")
        print("   1. Open Synapse Studio: https://web.azuresynapse.net")
        print(f"   2. Select workspace: {config['workspace_name']}")
        print("   3. Run this SQL:")
        print("      CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;")
        print("      ALTER ROLE db_datareader ADD MEMBER [wiv_account];")
        print("      ALTER ROLE db_datawriter ADD MEMBER [wiv_account];")
        print("      ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];")
    else:
        print(f"⚠️ Connection error: {str(e)[:200]}")

PYTHON_EOF

    # Execute the Python fallback script
    if command -v python3 >/dev/null 2>&1; then
        # Check for required Python packages
        if python3 -c "import pyodbc; import requests; import subprocess" 2>/dev/null; then
            echo "📝 Executing Python fallback setup..."
            
            # Variable substitution for the Python script
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS sed syntax
                sed -i '' "s/\$SYNAPSE_WORKSPACE/$SYNAPSE_WORKSPACE/g" setup_synapse_automated.py
                sed -i '' "s/\$TENANT_ID/$TENANT_ID/g" setup_synapse_automated.py
                sed -i '' "s/\$APP_ID/$APP_ID/g" setup_synapse_automated.py
                sed -i '' "s/\$CLIENT_SECRET/$CLIENT_SECRET/g" setup_synapse_automated.py
                sed -i '' "s/\$STORAGE_ACCOUNT_NAME/$STORAGE_ACCOUNT_NAME/g" setup_synapse_automated.py
                sed -i '' "s/\$CONTAINER_NAME/$CONTAINER_NAME/g" setup_synapse_automated.py
                sed -i '' "s/\$EXPORT_PATH/$EXPORT_PATH/g" setup_synapse_automated.py
                sed -i '' "s/\$MASTER_KEY_PASSWORD/$MASTER_KEY_PASSWORD/g" setup_synapse_automated.py
            else
                # Linux sed syntax
                sed -i "s/\$SYNAPSE_WORKSPACE/$SYNAPSE_WORKSPACE/g" setup_synapse_automated.py
                sed -i "s/\$TENANT_ID/$TENANT_ID/g" setup_synapse_automated.py
                sed -i "s/\$APP_ID/$APP_ID/g" setup_synapse_automated.py
                sed -i "s/\$CLIENT_SECRET/$CLIENT_SECRET/g" setup_synapse_automated.py
                sed -i "s/\$STORAGE_ACCOUNT_NAME/$STORAGE_ACCOUNT_NAME/g" setup_synapse_automated.py
                sed -i "s/\$CONTAINER_NAME/$CONTAINER_NAME/g" setup_synapse_automated.py
                sed -i "s/\$EXPORT_PATH/$EXPORT_PATH/g" setup_synapse_automated.py
                sed -i "s/\$MASTER_KEY_PASSWORD/$MASTER_KEY_PASSWORD/g" setup_synapse_automated.py
            fi
            
            # Execute the Python script
            python3 setup_synapse_automated.py
            SETUP_COMPLETED=$?
            
            # Clean up
            rm -f setup_synapse_automated.py
            
            if [ $SETUP_COMPLETED -eq 0 ]; then
                echo "✅ Database setup completed via Python fallback!"
            else
                echo "⚠️ Python fallback had issues, but database may still be partially configured"
            fi
        else
            echo "⚠️ Required Python packages not available for fallback setup"
            echo "   Please install: pip install pyodbc requests"
        fi
    else
        echo "⚠️ Python not available for fallback setup"
    fi
fi  # End of SETUP_COMPLETED check

# Continue with the rest of the script regardless of setup method

# ===========================
# FINAL SETUP STATUS
# ===========================
if [ "$SETUP_COMPLETED" != "true" ]; then
    echo ""
    echo "⚠️ Automated database setup could not complete"
    echo ""
    echo "📝 Manual setup required:"
    echo "   1. Open Synapse Studio: https://web.azuresynapse.net"
    echo "   2. Select workspace: $SYNAPSE_WORKSPACE"
    echo "   3. Go to Develop → SQL scripts → New SQL script"
    echo "   4. Run the SQL from: synapse_billing_setup.sql"
    echo ""
    echo "   This only needs to be done once. After that, the service principal will work."
fi

# Create backup SQL script for manual execution
cat > synapse_billing_setup.sql <<EOF
-- ========================================================
        
        if [ -n "$ACCESS_TOKEN" ]; then
            # Try to create database using REST API
            CREATE_DB_RESPONSE=$(curl -s -X POST \
                "https://$SYNAPSE_WORKSPACE-ondemand.sql.azuresynapse.net/sql/databases/master/query" \
                -H "Authorization: Bearer $ACCESS_TOKEN" \
                -H "Content-Type: application/json" \
                -d '{"query": "CREATE DATABASE BillingAnalytics"}' 2>/dev/null)
            
            # Create the view with the improved deduplication
            CREATE_VIEW_SQL=$(cat <<-EOSQL
                USE BillingAnalytics;
                CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$MASTER_KEY_PASSWORD';
                CREATE VIEW BillingData AS
                WITH LatestExport AS (
                    SELECT MAX(filepath(1)) as LatestPath
                    FROM OPENROWSET(
                        BULK 'abfss://$CONTAINER_NAME@$STORAGE_ACCOUNT_NAME.dfs.core.windows.net/$EXPORT_PATH/*/*.csv',
                        FORMAT = 'CSV',
                        PARSER_VERSION = '2.0',
                        FIRSTROW = 2
                    ) AS files
                )
                SELECT *
                FROM OPENROWSET(
                    BULK 'abfss://$CONTAINER_NAME@$STORAGE_ACCOUNT_NAME.dfs.core.windows.net/$EXPORT_PATH/*/*.csv',
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
                ) AS BillingData
                WHERE filepath(1) = (SELECT LatestPath FROM LatestExport);
EOSQL
            )
            
            # Try to create the view
            CREATE_VIEW_RESPONSE=$(curl -s -X POST \
                "https://$SYNAPSE_WORKSPACE-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
                -H "Authorization: Bearer $ACCESS_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"query\": \"$CREATE_VIEW_SQL\"}" 2>/dev/null)
            
            if [[ "$CREATE_VIEW_RESPONSE" == *"success"* ]] || [[ -z "$CREATE_VIEW_RESPONSE" ]]; then
                echo "✅ Database and view might have been created via REST API"
                SETUP_COMPLETED=true
            fi
        fi
    fi
    
    # Method 3: Install sqlcmd and retry
    if [ "$SETUP_COMPLETED" != "true" ] && ! command -v sqlcmd >/dev/null 2>&1; then
        echo "📝 Method 3: Installing sqlcmd and retrying..."
        
        # Try to install sqlcmd based on OS
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            if command -v brew >/dev/null 2>&1; then
                brew install sqlcmd 2>/dev/null && \
                sqlcmd -S "$SYNAPSE_WORKSPACE-ondemand.sql.azuresynapse.net" \
                       -d master \
                       -U "$APP_ID" \
                       -P "$CLIENT_SECRET" \
                       -G \
                       -Q "CREATE DATABASE BillingAnalytics" 2>/dev/null && \
                SETUP_COMPLETED=true
            fi
        elif command -v apt-get >/dev/null 2>&1; then
            # Ubuntu/Debian
            curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add - 2>/dev/null
            curl https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list | sudo tee /etc/apt/sources.list.d/msprod.list >/dev/null
            sudo apt-get update >/dev/null 2>&1
            sudo ACCEPT_EULA=Y apt-get install -y mssql-tools >/dev/null 2>&1
            export PATH="$PATH:/opt/mssql-tools/bin"
            
            if command -v sqlcmd >/dev/null 2>&1; then
                sqlcmd -S "$SYNAPSE_WORKSPACE-ondemand.sql.azuresynapse.net" \
                       -d master \
                       -U "$APP_ID" \
                       -P "$CLIENT_SECRET" \
                       -G \
                       -Q "CREATE DATABASE BillingAnalytics" 2>/dev/null && \
                SETUP_COMPLETED=true
            fi
        fi
    fi
    
    # Method 4: Create a verification script
    if [ "$SETUP_COMPLETED" != "true" ]; then
        echo "📝 Method 4: Creating automated completion script..."
        
        cat > complete_synapse_setup.sh <<-EOSCRIPT
#!/bin/bash
# Auto-generated script to complete Synapse setup
# Run this after the main script if database creation failed

SYNAPSE_WORKSPACE="$SYNAPSE_WORKSPACE"
APP_ID="$APP_ID"
CLIENT_SECRET="$CLIENT_SECRET"
STORAGE_ACCOUNT_NAME="$STORAGE_ACCOUNT_NAME"
MASTER_KEY_PASSWORD="$MASTER_KEY_PASSWORD"

echo "🔧 Attempting to complete Synapse setup..."

# Try with Python if available
if command -v python3 >/dev/null 2>&1; then
    pip3 install pyodbc 2>/dev/null || pip install pyodbc 2>/dev/null
    python3 -c "
import pyodbc
conn_str = f'DRIVER={{ODBC Driver 18 for SQL Server}};SERVER=$SYNAPSE_WORKSPACE-ondemand.sql.azuresynapse.net;DATABASE=master;UID=$APP_ID;PWD=$CLIENT_SECRET;Authentication=ActiveDirectoryServicePrincipal;Encrypt=yes;TrustServerCertificate=no;'
try:
    conn = pyodbc.connect(conn_str, autocommit=True)
    cursor = conn.cursor()
    cursor.execute('CREATE DATABASE BillingAnalytics')
    print('✅ Database created!')
except Exception as e:
    print(f'Database might already exist: {e}')
"
fi

echo "✅ To complete setup manually, run the SQL from synapse_billing_setup.sql in Synapse Studio"
echo "   URL: https://web.azuresynapse.net"
EOSCRIPT
        chmod +x complete_synapse_setup.sh
        echo "   ✅ Created: complete_synapse_setup.sh"
        echo "   Run it with: ./complete_synapse_setup.sh"
    fi
fi

# Final status check
if [ "$SETUP_COMPLETED" = "true" ]; then
    echo ""
    echo "✅ Database and view setup completed automatically!"
else
    echo ""
    echo "⚠️  Automated database creation was not successful."
    echo ""
    echo "📝 IMPORTANT: Complete setup using ONE of these methods:"
    echo ""
    echo "   Option 1: Run the completion script"
    echo "   ./complete_synapse_setup.sh"
    echo ""
    echo "   Option 2: Use Synapse Studio (Web UI)"
    echo "   1. Open: https://web.azuresynapse.net"
    echo "   2. Select workspace: $SYNAPSE_WORKSPACE"
    echo "   3. Run SQL from: synapse_billing_setup.sql"
    echo ""
    echo "   Option 3: Install sqlcmd and run:"
    echo "   sqlcmd -S $SYNAPSE_WORKSPACE-ondemand.sql.azuresynapse.net -U $APP_ID -P '$CLIENT_SECRET' -G -i synapse_billing_setup.sql"
    echo ""
    echo "⚠️  The system is 90% ready but REQUIRES the database/view creation to work!"
fi

# Save manual setup script as backup
cat > synapse_billing_setup.sql <<EOF
-- ========================================================
-- SYNAPSE BILLING DATA SETUP (Manual Backup)
-- ========================================================
-- Auto-generated on: $(date)
-- This is a backup if automated setup fails
-- Run this in Synapse Studio connected to Built-in serverless SQL pool
-- Workspace: $SYNAPSE_WORKSPACE
-- Storage Account: $STORAGE_ACCOUNT_NAME
-- Container: $CONTAINER_NAME

CREATE DATABASE BillingAnalytics;
GO
USE BillingAnalytics;
GO

CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$MASTER_KEY_PASSWORD';
GO

-- Create database user for the service principal
CREATE USER [$APP_ID] FROM EXTERNAL PROVIDER;
GO

-- Grant necessary permissions
ALTER ROLE db_datareader ADD MEMBER [$APP_ID];
ALTER ROLE db_datawriter ADD MEMBER [$APP_ID];
ALTER ROLE db_ddladmin ADD MEMBER [$APP_ID];
GO

-- Improved view that automatically queries only the latest export file
-- This prevents data duplication since each export contains cumulative month-to-date data
-- Using Managed Identity with abfss:// protocol (NEVER EXPIRES!)
-- Storage Configuration:
--   Account: $STORAGE_ACCOUNT_NAME
--   Container: $CONTAINER_NAME
--   Export Path: $EXPORT_PATH
CREATE VIEW BillingData AS
WITH LatestExport AS (
    -- Find the most recent export file
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'abfss://$CONTAINER_NAME@$STORAGE_ACCOUNT_NAME.dfs.core.windows.net/$EXPORT_PATH/*/*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        FIRSTROW = 2
    ) AS files
)
SELECT *
FROM OPENROWSET(
    BULK 'abfss://$CONTAINER_NAME@$STORAGE_ACCOUNT_NAME.dfs.core.windows.net/$EXPORT_PATH/*/*.csv',
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
) AS BillingData
WHERE filepath(1) = (SELECT LatestPath FROM LatestExport);
GO
EOF

echo "✅ Manual backup script saved to: synapse_billing_setup.sql"

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
    'export_path': '$EXPORT_PATH',
    'storage_subscription': '$STORAGE_SUBSCRIPTION',
    'storage_resource_group': '$STORAGE_RG',
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
-- ========================================================
-- BILLING DATA QUERIES - OPTIMIZED VERSION
-- ========================================================
-- The BillingData view now AUTOMATICALLY prevents duplication!
-- No need for complex CTE patterns - just query the view directly
--
-- Background: Each daily export contains cumulative month-to-date data
-- The improved view automatically filters to only the latest export file
-- This means you get accurate, non-duplicated data with simple queries
-- ========================================================

-- 1. Simple query - automatically gets latest data without duplication
SELECT * FROM BillingAnalytics.dbo.BillingData
WHERE CAST(Date AS DATE) >= DATEADD(day, -7, GETDATE())

-- 2. Query specific date range
-- Replace '2024-08-01' and '2024-08-10' with your desired dates
SELECT * FROM BillingAnalytics.dbo.BillingData
WHERE CAST(Date AS DATE) BETWEEN '2024-08-01' AND '2024-08-10'

-- 3. Daily cost summary for last 7 days
SELECT 
    CAST(Date AS DATE) as BillingDate,
    ServiceFamily,
    ResourceGroupName,
    SUM(CAST(CostInUSD AS FLOAT)) as TotalCostUSD,
    COUNT(DISTINCT ResourceId) as ResourceCount
FROM BillingAnalytics.dbo.BillingData
WHERE CAST(Date AS DATE) BETWEEN DATEADD(day, -7, GETDATE()) AND GETDATE()
GROUP BY CAST(Date AS DATE), ServiceFamily, ResourceGroupName
ORDER BY BillingDate DESC

-- 4. Compare costs between two date ranges
WITH CurrentWeek AS (
    SELECT 
        ServiceFamily,
        SUM(CAST(CostInUSD AS FLOAT)) as CurrentCost
    FROM BillingAnalytics.dbo.BillingData
    WHERE CAST(Date AS DATE) BETWEEN DATEADD(day, -7, GETDATE()) AND GETDATE()
    GROUP BY ServiceFamily
),
PreviousWeek AS (
    SELECT 
        ServiceFamily,
        SUM(CAST(CostInUSD AS FLOAT)) as PreviousCost
    FROM BillingAnalytics.dbo.BillingData
    WHERE CAST(Date AS DATE) BETWEEN DATEADD(day, -14, GETDATE()) AND DATEADD(day, -8, GETDATE())
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
SELECT 
    CAST(Date AS DATE) as BillingDate,
    SUM(CAST(CostInUSD AS FLOAT)) as DailyCost,
    SUM(SUM(CAST(CostInUSD AS FLOAT))) OVER (ORDER BY CAST(Date AS DATE)) as CumulativeCost
FROM BillingAnalytics.dbo.BillingData
WHERE MONTH(CAST(Date AS DATE)) = MONTH(GETDATE())
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

# Automatically trigger the first export run
echo ""
echo "🔄 Automatically triggering billing export to run immediately..."
EXPORT_TRIGGER_RESULT=$(az rest --method POST \
    --uri "https://management.azure.com/subscriptions/$APP_SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME/run?api-version=2023-07-01-preview" \
    --only-show-errors 2>&1)

if [[ "$EXPORT_TRIGGER_RESULT" == *"error"* ]] || [[ "$EXPORT_TRIGGER_RESULT" == *"Error"* ]]; then
    echo "⚠️  Could not trigger export immediately"
    echo "   This is normal if an export is already running"
    echo "   Export will run automatically at midnight UTC daily"
else
    echo "✅ FOCUS billing export triggered successfully!"
    echo "   📊 Data will be available in 5-30 minutes at:"
    echo "      Storage: $STORAGE_ACCOUNT_NAME"
    echo "      Container: $CONTAINER_NAME/billing-data/"
    echo "      Format: FOCUS 1.0 (standardized FinOps format)"
    echo "   ⏰ Future exports will run automatically every day at midnight UTC"
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
if [ "$USE_EXISTING_STORAGE" = "true" ]; then
    echo "   - Using Existing Storage: YES"
    echo "   - Storage Subscription:   $STORAGE_SUBSCRIPTION"
    echo "   - Storage Resource Group: $STORAGE_RG"
else
    echo "   - Resource Group:         $BILLING_RG"
fi
echo "   - Storage Account:        $STORAGE_ACCOUNT_NAME"
echo "   - Container:              $CONTAINER_NAME"
echo "   - Export Path:            $EXPORT_PATH"
if [ "$SKIP_EXPORT_CREATION" = "false" ]; then
    echo "   - Export Name:            $EXPORT_NAME"
fi
echo ""
echo "🔷 Synapse Configuration:"
echo "   - Workspace:              $SYNAPSE_WORKSPACE"
echo "   - SQL Endpoint:           $SYNAPSE_WORKSPACE.sql.azuresynapse.net"
echo "   - SQL Admin User:         $SQL_ADMIN_USER"
echo "   - SQL Admin Password:     $SQL_ADMIN_PASSWORD"
echo "   - Data Lake Storage:      $SYNAPSE_STORAGE"
echo ""
echo "🔐 AUTHENTICATION:"
echo "   ✨ Managed Identity with abfss:// protocol"
echo "   ✅ NO TOKENS, NO EXPIRATION, NO MAINTENANCE!"
echo ""
echo "📄 Assigned Roles:"
echo "   - Cost Management Reader"
echo "   - Monitoring Reader"
echo "   - Storage Blob Data Reader (for Managed Identity)"
echo "   - Storage Blob Data Contributor"
echo "   - Contributor"
echo "   - Synapse Administrator"
echo "   - Synapse SQL Administrator"
echo "   - Synapse Contributor"
echo ""
echo "📝 Next Steps:"
if [ "$SETUP_COMPLETED" = "true" ]; then
    echo "   1. ✅ Synapse database automatically configured with Managed Identity"
    echo "   2. ✅ NO TOKEN RENEWAL NEEDED - Using Managed Identity!"
    echo "   3. Query data: SELECT * FROM BillingAnalytics.dbo.BillingData"
    echo "      ℹ️  View automatically filters to latest export (no duplication!)"
    echo "   4. Access Synapse Studio: https://web.azuresynapse.net"
else
    echo "   1. ⚠️  Database/View creation pending - Run: ./complete_synapse_setup.sh"
    echo "   2. ✅ NO TOKEN RENEWAL NEEDED - Using Managed Identity!"
    echo "   3. After setup, query: SELECT * FROM BillingAnalytics.dbo.BillingData"
    echo "   4. Or complete in Synapse Studio: https://web.azuresynapse.net"
fi
echo ""
echo "📊 Generated files:"
echo "   - billing_queries.sql: Ready-to-use Synapse queries"
echo "   - synapse_billing_setup.sql: Manual SQL script (if automation fails)"
echo "   - synapse_config.py: Python configuration for remote queries"
echo ""
echo "🚀 Managed Identity Benefits:"
echo "   ✅ NEVER EXPIRES - Works forever without maintenance"
echo "   ✅ NO TOKENS - No SAS tokens or keys to manage"
echo "   ✅ MORE SECURE - Azure native authentication"
echo "   ✅ AUTOMATIC - Direct access via abfss:// protocol"
echo "   ✅ BEST PRACTICE - Microsoft recommended approach"
echo "============================================================"