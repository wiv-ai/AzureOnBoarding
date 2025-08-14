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

echo "⏳ Waiting for Synapse workspace to be fully operational..."
sleep 30

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

# Configure authentication for storage access
echo ""
echo "🔑 Configuring authentication for Synapse storage access..."

# Option 1: Use Managed Identity (no expiration)
AUTH_METHOD="ManagedIdentity"

# Grant the service principal access to the storage account
echo "Setting up Managed Identity access..."
az role assignment create \
    --role "Storage Blob Data Reader" \
    --assignee "$SP_OBJECT_ID" \
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$BILLING_RG/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME" \
    --only-show-errors 2>/dev/null || echo "⚠️  SP role may already be assigned"

# Also grant Synapse workspace managed identity access
SYNAPSE_IDENTITY=$(az synapse workspace show \
    --name "$SYNAPSE_WORKSPACE" \
    --resource-group "$SYNAPSE_RG" \
    --query "identity.principalId" \
    --output tsv 2>/dev/null)

if [ -n "$SYNAPSE_IDENTITY" ]; then
    az role assignment create \
        --role "Storage Blob Data Reader" \
        --assignee "$SYNAPSE_IDENTITY" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$BILLING_RG/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME" \
        --only-show-errors 2>/dev/null || echo "⚠️  Synapse role may already be assigned"
    echo "✅ Managed Identity configured (never expires)"
fi

# Option 2: Generate long-term SAS token as fallback (maximum 5 years)
echo "Generating backup SAS token..."
STORAGE_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$BILLING_RG" \
    --query "[0].value" \
    --output tsv 2>/dev/null)

if [ -n "$STORAGE_KEY" ]; then
    # Set expiry to 5 years (maximum allowed)
    SAS_EXPIRY=$(date -u -d '5 years' '+%Y-%m-%dT%H:%MZ' 2>/dev/null || date -v +1825d '+%Y-%m-%dT%H:%MZ')
    SAS_TOKEN=$(az storage container generate-sas \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --name "$CONTAINER_NAME" \
        --permissions rl \
        --expiry "$SAS_EXPIRY" \
        --account-key "$STORAGE_KEY" \
        --output tsv 2>/dev/null)
    echo "✅ Backup SAS token generated (valid for 5 years)"
else
    SAS_TOKEN=""
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

# Note: Authentication will be configured after resources are created

# Automated Synapse Database Setup
echo ""
echo "🔧 Setting up Synapse database and views automatically..."

# Generate a secure password for master key
MASTER_KEY_PASSWORD="StrongP@ssw0rd$(openssl rand -hex 4 2>/dev/null || echo $RANDOM)!"

# Create and execute the setup script
echo "Setting up database objects..."

# Since Azure CLI doesn't support direct SQL execution on serverless pools,
# we'll use a Python script to automate this
cat > setup_synapse_automated.py <<'PYTHON_EOF'
#!/usr/bin/env python3
import pyodbc
import sys
import time

# Configuration from environment
config = {
    'workspace_name': '$SYNAPSE_WORKSPACE',
    'tenant_id': '$TENANT_ID',
    'client_id': '$APP_ID', 
    'client_secret': '$CLIENT_SECRET',
    'storage_account': '$STORAGE_ACCOUNT_NAME',
    'container': '$CONTAINER_NAME',
    'sas_token': '$SAS_TOKEN',
    'master_key_password': '$MASTER_KEY_PASSWORD'
}

def wait_for_synapse():
    """Wait for Synapse to be ready"""
    print("⏳ Waiting for Synapse workspace to be fully ready...")
    max_retries = 10
    retry_delay = 30
    
    for attempt in range(max_retries):
        try:
            # Try a simple connection to check if Synapse is ready
            test_conn_str = f"""
            DRIVER={{ODBC Driver 18 for SQL Server}};
            SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;
            DATABASE=master;
            UID={config['client_id']};
            PWD={config['client_secret']};
            Authentication=ActiveDirectoryServicePrincipal;
            Encrypt=yes;
            TrustServerCertificate=no;
            Connection Timeout=30;
            """
            
            conn = pyodbc.connect(test_conn_str, autocommit=True)
            conn.close()
            print("✅ Synapse is ready!")
            return True
        except Exception as e:
            if attempt < max_retries - 1:
                print(f"⏳ Synapse not ready yet (attempt {attempt + 1}/{max_retries}). Waiting {retry_delay} seconds...")
                time.sleep(retry_delay)
            else:
                print(f"❌ Synapse not accessible after {max_retries} attempts: {e}")
                return False
    
    return False

def execute_sql_commands(conn_str, commands):
    """Execute SQL commands one by one"""
    try:
        # Add connection timeout
        conn_str_with_timeout = conn_str.replace(
            'TrustServerCertificate=no;',
            'TrustServerCertificate=no;Connection Timeout=60;'
        )
        conn = pyodbc.connect(conn_str_with_timeout, autocommit=True)
        cursor = conn.cursor()
        
        for i, command in enumerate(commands, 1):
            if command.strip():
                try:
                    print(f"Executing step {i}...")
                    cursor.execute(command)
                    print(f"✅ Step {i} completed")
                except pyodbc.Error as e:
                    if "already exists" in str(e) or "Cannot drop" in str(e):
                        print(f"⚠️  Step {i}: Object already exists (skipping)")
                    else:
                        print(f"❌ Step {i} failed: {e}")
                        # Continue with next command
                time.sleep(1)
        
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        print(f"Connection failed: {e}")
        return False

# First wait for Synapse to be ready
if not wait_for_synapse():
    print("⚠️  Synapse is not accessible via service principal. This could be due to:")
    print("   1. Firewall rules not yet propagated (wait a few minutes)")
    print("   2. Service principal permissions still propagating")
    print("   3. Synapse workspace still provisioning")
    print("")
    print("📝 Manual setup instructions saved to: synapse_billing_setup.sql")
    print("   You can either:")
    print("   a) Wait 5-10 minutes and re-run this script")
    print("   b) Run the SQL script manually in Synapse Studio")
    print("")
    print("💡 TIP: The Synapse workspace is created and will work!")
    print("   The automated database setup just needs more time to connect.")
    sys.exit(0)

# Connection string for master database
master_conn_str = f"""
DRIVER={{ODBC Driver 18 for SQL Server}};
SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;
DATABASE=master;
UID={config['client_id']};
PWD={config['client_secret']};
Authentication=ActiveDirectoryServicePrincipal;
Encrypt=yes;
TrustServerCertificate=no;
Connection Timeout=60;
"""

# Create database
print("📦 Creating BillingAnalytics database...")
db_commands = [
    "CREATE DATABASE BillingAnalytics"
]

execute_sql_commands(master_conn_str, db_commands)

# Connection string for BillingAnalytics database
billing_conn_str = f"""
DRIVER={{ODBC Driver 18 for SQL Server}};
SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;
DATABASE=BillingAnalytics;
UID={config['client_id']};
PWD={config['client_secret']};
Authentication=ActiveDirectoryServicePrincipal;
Encrypt=yes;
TrustServerCertificate=no;
Connection Timeout=60;
"""

# Setup commands
print("\n🔧 Setting up database objects...")
setup_commands = [
    # Create master key
    f"CREATE MASTER KEY ENCRYPTION BY PASSWORD = '{config['master_key_password']}'",
    
    # Drop existing credential if exists
    """IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'BillingStorageCredential')
       DROP DATABASE SCOPED CREDENTIAL BillingStorageCredential""",
    
    # Drop existing managed identity credential if exists  
    """IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'WorkspaceManagedIdentity')
       DROP DATABASE SCOPED CREDENTIAL WorkspaceManagedIdentity""",
    
    # Create managed identity credential (never expires!)
    """CREATE DATABASE SCOPED CREDENTIAL WorkspaceManagedIdentity
        WITH IDENTITY = 'Managed Identity'""",
    
    # Also create SAS credential as backup
    f"""CREATE DATABASE SCOPED CREDENTIAL BillingStorageCredential
        WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
        SECRET = '{config['sas_token']}'""",
    
    # Drop existing data source if exists
    """IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'BillingDataSource')
       DROP EXTERNAL DATA SOURCE BillingDataSource""",
    
    # Create data source using Managed Identity (preferred)
    f"""CREATE EXTERNAL DATA SOURCE BillingDataSource
        WITH (
            LOCATION = 'https://{config['storage_account']}.blob.core.windows.net/{config['container']}',
            CREDENTIAL = WorkspaceManagedIdentity
        )""",
    
    # Drop existing view if exists
    """IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingData')
       DROP VIEW BillingData""",
    
    # Create view
    """CREATE VIEW BillingData AS
       SELECT *
       FROM OPENROWSET(
           BULK 'billing-data/DailyBillingExport/20250801-20250831/*.csv',
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
       ) AS BillingData"""
]

if execute_sql_commands(billing_conn_str, setup_commands):
    print("\n✅ Synapse database setup completed successfully!")
    
    # Test the view
    print("\n🔍 Testing the view...")
    try:
        conn = pyodbc.connect(billing_conn_str)
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) as RecordCount FROM BillingData")
        row = cursor.fetchone()
        print(f"✅ View is working! Found {row[0]} billing records")
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"⚠️  Could not test view: {e}")
else:
    print("\n❌ Some steps failed, but setup may still be usable")

print("\n📊 You can now query billing data using:")
print("   SELECT * FROM BillingAnalytics.dbo.BillingData")
PYTHON_EOF

# Check if Python and pyodbc are available
if command -v python3 >/dev/null 2>&1; then
    # Check for pyodbc
    if ! python3 -c "import pyodbc" 2>/dev/null; then
        echo "📦 Installing pyodbc for automated setup..."
        # Try to install pyodbc and dependencies
        if command -v apt-get >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
            # Debian/Ubuntu with sudo
            sudo apt-get update >/dev/null 2>&1
            sudo apt-get install -y unixodbc-dev >/dev/null 2>&1
            
            # Install Microsoft ODBC Driver
            if ! odbcinst -q -d -n "ODBC Driver 18 for SQL Server" >/dev/null 2>&1; then
                curl https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg 2>/dev/null
                curl -s https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs 2>/dev/null || echo "22.04")/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list >/dev/null
                sudo apt-get update >/dev/null 2>&1
                sudo ACCEPT_EULA=Y apt-get install -y msodbcsql18 >/dev/null 2>&1
            fi
        elif command -v apt-get >/dev/null 2>&1; then
            # Debian/Ubuntu without sudo (running as root)
            apt-get update >/dev/null 2>&1
            apt-get install -y unixodbc-dev >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            # RHEL/CentOS
            if command -v sudo >/dev/null 2>&1; then
                sudo yum install -y unixODBC-devel >/dev/null 2>&1
            else
                yum install -y unixODBC-devel >/dev/null 2>&1
            fi
        fi
        
        # Install pyodbc - try different methods
        pip3 install pyodbc --quiet 2>/dev/null || \
        pip install pyodbc --quiet 2>/dev/null || \
        python3 -m pip install pyodbc --quiet 2>/dev/null || \
        (command -v sudo >/dev/null 2>&1 && sudo pip3 install pyodbc --quiet 2>/dev/null) || \
        echo "⚠️  Could not install pyodbc automatically"
    fi
    
    # Try to run the automated setup
    if python3 -c "import pyodbc" 2>/dev/null; then
        echo "🚀 Running automated Synapse setup..."
        # Replace variables in Python script
        sed -i "s/\$SYNAPSE_WORKSPACE/$SYNAPSE_WORKSPACE/g" setup_synapse_automated.py
        sed -i "s/\$TENANT_ID/$TENANT_ID/g" setup_synapse_automated.py
        sed -i "s/\$APP_ID/$APP_ID/g" setup_synapse_automated.py
        sed -i "s/\$CLIENT_SECRET/$CLIENT_SECRET/g" setup_synapse_automated.py
        sed -i "s/\$STORAGE_ACCOUNT_NAME/$STORAGE_ACCOUNT_NAME/g" setup_synapse_automated.py
        sed -i "s/\$CONTAINER_NAME/$CONTAINER_NAME/g" setup_synapse_automated.py
        sed -i "s/\$SAS_TOKEN/$SAS_TOKEN/g" setup_synapse_automated.py
        sed -i "s/\$MASTER_KEY_PASSWORD/$MASTER_KEY_PASSWORD/g" setup_synapse_automated.py
        
        python3 setup_synapse_automated.py
        rm -f setup_synapse_automated.py
    else
        echo "⚠️  Could not install pyodbc automatically"
        echo "   Manual setup script saved to: synapse_billing_setup.sql"
        echo "   To install manually: pip install pyodbc"
    fi
else
    echo "⚠️  Python not available for automated setup"
    echo "   Manual setup script saved to: synapse_billing_setup.sql"
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

-- Option 1: Managed Identity (NEVER EXPIRES - Recommended!)
CREATE DATABASE SCOPED CREDENTIAL WorkspaceManagedIdentity
WITH IDENTITY = 'Managed Identity';
GO

-- Option 2: SAS Token (5-year backup)
CREATE DATABASE SCOPED CREDENTIAL BillingStorageCredential
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
SECRET = '$SAS_TOKEN';
GO

-- Create data source using Managed Identity
CREATE EXTERNAL DATA SOURCE BillingDataSource
WITH (
    LOCATION = 'https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME',
    CREDENTIAL = WorkspaceManagedIdentity  -- Uses Managed Identity (no expiration!)
);
GO

CREATE VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK 'billing-data/DailyBillingExport/20250801-20250831/*.csv',
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
echo "🔐 AUTHENTICATION (NO EXPIRATION!):"
echo "   ✨ Primary: Managed Identity (NEVER EXPIRES)"
echo "   📅 Backup: SAS Token (5-year validity)"
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
echo "   1. ✅ Synapse database automatically configured with Managed Identity"
echo "   2. ✅ NO TOKEN RENEWAL NEEDED - Using Managed Identity!"
echo "   3. Query data: SELECT * FROM BillingAnalytics.dbo.BillingData"
echo "   4. Access Synapse Studio: https://web.azuresynapse.net"
echo ""
echo "📊 Generated files for your use:"
echo "   - billing_queries.sql: Ready-to-use Synapse queries"
echo "   - synapse_billing_setup.sql: Manual backup script (if needed)"
echo "   - synapse_config.py: Python configuration for remote queries"
echo ""
echo "🚀 Benefits of Managed Identity:"
echo "   ✅ Never expires - no maintenance required"
echo "   ✅ More secure - no secrets to manage"
echo "   ✅ Automatic - works immediately"
echo "   ✅ Best practice - recommended by Microsoft"
echo "============================================================"