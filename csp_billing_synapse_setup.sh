#!/bin/bash

# ====================================================================================================
# Azure CSP Billing Export with Synapse Analytics Setup Script
# ====================================================================================================
# This script sets up automated billing exports for CSP partners with FOCUS format
# and creates Synapse Analytics for querying consolidated customer billing data
# ====================================================================================================

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=====================================================================================================${NC}"
echo -e "${BLUE}                    Azure CSP Billing Export with Synapse Analytics Setup                           ${NC}"
echo -e "${BLUE}=====================================================================================================${NC}"
echo ""

# ===========================
# STEP 1: LOGIN & SERVICE PRINCIPAL
# ===========================
echo -e "${YELLOW}Step 1: Authentication and Service Principal Setup${NC}"
echo "--------------------------------------"

# Login to Azure
echo "🔐 Logging into Azure..."
az login --output none

# Get Tenant ID
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Tenant ID: $TENANT_ID"

# Service Principal Setup
APP_DISPLAY_NAME="wiv_account"
echo ""
echo "🔐 Checking for service principal '$APP_DISPLAY_NAME'..."
APP_ID=$(az ad sp list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv 2>/dev/null)

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
  echo ""
  echo "⚠️  IMPORTANT: Save these credentials NOW! The secret cannot be retrieved later:"
  echo "   Tenant ID: $TENANT_ID"
  echo "   Client ID (App ID): $APP_ID"
  echo "   Client Secret: $CLIENT_SECRET"
  echo ""
  read -p "Press Enter once you've saved the credentials..."
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
      echo "  2. Find '$APP_DISPLAY_NAME' (App ID: $APP_ID)"
      echo "  3. Go to 'Certificates & secrets' > 'Client secrets'"
      echo "  4. Click 'New client secret' and save the value"
      echo ""
      exit 1
    fi
    
    echo "✅ Client secret provided"
  fi
fi

# ===========================
# STEP 2: DISCOVER CSP BILLING ACCOUNT
# ===========================
echo ""
echo -e "${YELLOW}Step 2: CSP Billing Account Discovery${NC}"
echo "--------------------------------------"
echo -e "${GREEN}🔍 Discovering CSP Billing Accounts...${NC}"
echo "--------------------------------------"

# Query for CSP billing accounts (Microsoft Customer Agreement)
BILLING_ACCOUNTS=$(az rest --method GET \
    --uri "https://management.azure.com/providers/Microsoft.Billing/billingAccounts?api-version=2020-05-01" \
    --query "value[?agreementType=='MicrosoftCustomerAgreement'].[name, displayName, agreementType]" \
    -o json)

if [ "$BILLING_ACCOUNTS" == "[]" ]; then
    echo -e "${RED}❌ No CSP (Microsoft Customer Agreement) billing accounts found.${NC}"
    echo "   Please ensure you have access to a CSP billing account."
    exit 1
fi

echo -e "${GREEN}Found CSP Billing Account(s):${NC}"
echo "$BILLING_ACCOUNTS" | jq -r '.[] | "  📋 ID: \(.[0])\n     Name: \(.[1])\n     Type: \(.[2])\n"'

# If multiple accounts, let user choose
ACCOUNT_COUNT=$(echo "$BILLING_ACCOUNTS" | jq '. | length')

if [ "$ACCOUNT_COUNT" -gt 1 ]; then
    echo ""
    echo "Multiple CSP billing accounts found. Please select one:"
    select_account=0
    while [ $select_account -lt 1 ] || [ $select_account -gt $ACCOUNT_COUNT ]; do
        read -p "Enter the number (1-$ACCOUNT_COUNT): " select_account
    done
    CSP_BILLING_ACCOUNT_ID=$(echo "$BILLING_ACCOUNTS" | jq -r ".[$((select_account-1))][0]")
    CSP_BILLING_ACCOUNT_NAME=$(echo "$BILLING_ACCOUNTS" | jq -r ".[$((select_account-1))][1]")
else
    CSP_BILLING_ACCOUNT_ID=$(echo "$BILLING_ACCOUNTS" | jq -r ".[0][0]")
    CSP_BILLING_ACCOUNT_NAME=$(echo "$BILLING_ACCOUNTS" | jq -r ".[0][1]")
fi

echo ""
echo -e "${GREEN}✅ Selected CSP Billing Account:${NC}"
echo "   ID: $CSP_BILLING_ACCOUNT_ID"
echo "   Name: $CSP_BILLING_ACCOUNT_NAME"

# ===========================
# STEP 3: GET MANAGEMENT SUBSCRIPTION
# ===========================
echo ""
echo -e "${YELLOW}Step 3: Select Management Subscription for Resources${NC}"
echo "--------------------------------------"
echo "This is where rg-wiv and all management resources will be created."
echo ""

# List available subscriptions
SUBSCRIPTIONS=$(az account list --query "[?state=='Enabled'].[id, name]" -o json)

echo "Available subscriptions:"
echo "$SUBSCRIPTIONS" | jq -r '.[] | "  📁 \(.[1]) (\(.[0]))"'

echo ""
read -p "Enter the Management Subscription ID where rg-wiv will be created: " MGMT_SUBSCRIPTION_ID

# Validate subscription exists
if ! az account show --subscription "$MGMT_SUBSCRIPTION_ID" &>/dev/null; then
    echo -e "${RED}❌ Invalid subscription ID. Please run the script again.${NC}"
    exit 1
fi

# Set the subscription context
az account set --subscription "$MGMT_SUBSCRIPTION_ID"
MGMT_SUBSCRIPTION_NAME=$(az account show --subscription "$MGMT_SUBSCRIPTION_ID" --query name -o tsv)

echo -e "${GREEN}✅ Management Subscription set to: $MGMT_SUBSCRIPTION_NAME${NC}"

# ===========================
# STEP 4: CHECK EXISTING RESOURCES
# ===========================
echo ""
echo -e "${YELLOW}Step 4: Check for Existing Resources${NC}"
echo "--------------------------------------"

# Check if billing export already exists
echo "🔍 Checking for existing billing exports..."
EXISTING_EXPORTS=$(az rest --method GET \
    --uri "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$CSP_BILLING_ACCOUNT_ID/providers/Microsoft.CostManagement/exports?api-version=2023-11-01" \
    --query "value[].name" -o json 2>/dev/null || echo "[]")

if [ "$EXISTING_EXPORTS" != "[]" ]; then
    echo -e "${YELLOW}⚠️  Found existing billing export(s):${NC}"
    echo "$EXISTING_EXPORTS" | jq -r '.[]'
    echo ""
    read -p "Do you want to use an existing export? (y/n): " USE_EXISTING_EXPORT
    
    if [[ "$USE_EXISTING_EXPORT" =~ ^[Yy]$ ]]; then
        echo "Select an export:"
        select export_name in $(echo "$EXISTING_EXPORTS" | jq -r '.[]'); do
            EXPORT_NAME="$export_name"
            break
        done
        
        # Get export details
        EXPORT_DETAILS=$(az rest --method GET \
            --uri "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$CSP_BILLING_ACCOUNT_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME?api-version=2023-11-01")
        
        STORAGE_RESOURCE_ID=$(echo "$EXPORT_DETAILS" | jq -r '.properties.deliveryInfo.destination.resourceId')
        CONTAINER_NAME=$(echo "$EXPORT_DETAILS" | jq -r '.properties.deliveryInfo.destination.container')
        ROOT_FOLDER=$(echo "$EXPORT_DETAILS" | jq -r '.properties.deliveryInfo.destination.rootFolderPath')
        
        # Extract storage account name from resource ID
        STORAGE_ACCOUNT_NAME=$(echo "$STORAGE_RESOURCE_ID" | sed 's/.*storageAccounts\///' | sed 's/\/.*//')
        
        echo -e "${GREEN}✅ Using existing export: $EXPORT_NAME${NC}"
        echo "   Storage Account: $STORAGE_ACCOUNT_NAME"
        echo "   Container: $CONTAINER_NAME"
        echo "   Path: $ROOT_FOLDER"
        
        SKIP_EXPORT_CREATION="true"
    else
        SKIP_EXPORT_CREATION="false"
    fi
else
    echo "No existing exports found."
    SKIP_EXPORT_CREATION="false"
fi

# ===========================
# STEP 5: GATHER CONFIGURATION
# ===========================
echo ""
echo -e "${YELLOW}Step 5: Configuration Settings${NC}"
echo "--------------------------------------"

# Get resource group name
read -p "Enter resource group name [rg-wiv]: " RESOURCE_GROUP
RESOURCE_GROUP=${RESOURCE_GROUP:-rg-wiv}

# Get location
read -p "Enter Azure region (e.g., eastus, westeurope) [eastus]: " LOCATION
LOCATION=${LOCATION:-eastus}

# If not using existing export, get storage details
if [ "$SKIP_EXPORT_CREATION" == "false" ]; then
    echo ""
    echo "📦 Storage Configuration for Billing Export:"
    
    # Check for existing storage accounts in the resource group
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        EXISTING_STORAGE=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[].name" -o json 2>/dev/null || echo "[]")
        
        if [ "$EXISTING_STORAGE" != "[]" ]; then
            echo -e "${YELLOW}Found existing storage account(s) in $RESOURCE_GROUP:${NC}"
            echo "$EXISTING_STORAGE" | jq -r '.[]'
            echo ""
            read -p "Do you want to use an existing storage account? (y/n): " USE_EXISTING_STORAGE
            
            if [[ "$USE_EXISTING_STORAGE" =~ ^[Yy]$ ]]; then
                echo "Select a storage account:"
                select storage_name in $(echo "$EXISTING_STORAGE" | jq -r '.[]'); do
                    STORAGE_ACCOUNT_NAME="$storage_name"
                    break
                done
                SKIP_STORAGE_CREATION="true"
            else
                STORAGE_ACCOUNT_NAME="cspbilling$(date +%s)"
                echo "Will create new storage account: $STORAGE_ACCOUNT_NAME"
                SKIP_STORAGE_CREATION="false"
            fi
        else
            STORAGE_ACCOUNT_NAME="cspbilling$(date +%s)"
            echo "Will create new storage account: $STORAGE_ACCOUNT_NAME"
            SKIP_STORAGE_CREATION="false"
        fi
    else
        STORAGE_ACCOUNT_NAME="cspbilling$(date +%s)"
        echo "Will create new storage account: $STORAGE_ACCOUNT_NAME"
        SKIP_STORAGE_CREATION="false"
    fi
    
    read -p "Enter container name for billing exports [billing-exports]: " CONTAINER_NAME
    CONTAINER_NAME=${CONTAINER_NAME:-billing-exports}
    
    read -p "Enter root folder path [csp-billing-data]: " ROOT_FOLDER
    ROOT_FOLDER=${ROOT_FOLDER:-csp-billing-data}
    
    read -p "Enter export name [CSPDailyExport]: " EXPORT_NAME
    EXPORT_NAME=${EXPORT_NAME:-CSPDailyExport}
fi

# Synapse configuration
echo ""
echo "📊 Synapse Analytics Configuration:"
UNIQUE_SUFFIX=$(date +%s | tail -c 6)
read -p "Enter Synapse workspace name [wiv-synapse-$UNIQUE_SUFFIX]: " SYNAPSE_WORKSPACE
SYNAPSE_WORKSPACE=${SYNAPSE_WORKSPACE:-wiv-synapse-$UNIQUE_SUFFIX}

# ===========================
# STEP 6: SET PERMISSIONS
# ===========================
echo ""
echo -e "${YELLOW}Step 6: Setting up Permissions${NC}"
echo "--------------------------------------"

# Assign Cost Management Reader at billing account level
echo "🔒 Assigning Cost Management Reader at CSP billing account level..."
az role assignment create \
    --assignee "$APP_ID" \
    --role "Cost Management Reader" \
    --scope "/providers/Microsoft.Billing/billingAccounts/$CSP_BILLING_ACCOUNT_ID" \
    --only-show-errors 2>/dev/null || echo "   Note: Permission might already exist"

echo "✅ Billing permissions configured"

# ===========================
# STEP 7: CREATE RESOURCES
# ===========================
echo ""
echo -e "${YELLOW}Step 7: Creating Resources in Management Subscription${NC}"
echo "--------------------------------------"

# Create resource group
echo "📁 Creating resource group: $RESOURCE_GROUP..."
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output none

echo -e "${GREEN}✅ Resource group created${NC}"

# Create storage account if needed
if [ "$SKIP_STORAGE_CREATION" == "false" ] && [ "$SKIP_EXPORT_CREATION" == "false" ]; then
    echo "📦 Creating storage account: $STORAGE_ACCOUNT_NAME..."
    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --output none
    
    # Create container
    echo "📁 Creating container: $CONTAINER_NAME..."
    az storage container create \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --auth-mode login \
        --output none
    
    echo -e "${GREEN}✅ Storage account and container created${NC}"
    
    # Get storage resource ID
    STORAGE_RESOURCE_ID="/subscriptions/$MGMT_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME"
fi

# ===========================
# STEP 8: CREATE BILLING EXPORT
# ===========================
if [ "$SKIP_EXPORT_CREATION" == "false" ]; then
    echo ""
    echo -e "${YELLOW}Step 8: Creating CSP Billing Export (FOCUS Format)${NC}"
    echo "--------------------------------------"
    echo "📊 Export Configuration:"
    echo "   Type: Cost and usage details (FOCUS)"
    echo "   Version: 1.0"
    echo "   Format: CSV"
    echo "   Compression: None"
    echo "   Overwrite: Yes"
    echo "   Schedule: Daily"
    
    # Create the export with FOCUS format
    EXPORT_BODY=$(cat <<EOF
{
  "properties": {
    "schedule": {
      "status": "Active",
      "recurrence": "Daily",
      "recurrencePeriod": {
        "from": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "to": "$(date -u -d '+1 year' +%Y-%m-%dT%H:%M:%SZ)"
      }
    },
    "format": "Csv",
    "deliveryInfo": {
      "destination": {
        "resourceId": "$STORAGE_RESOURCE_ID",
        "container": "$CONTAINER_NAME",
        "rootFolderPath": "$ROOT_FOLDER"
      }
    },
    "definition": {
      "type": "FocusCost",
      "dataSet": {
        "granularity": "Daily",
        "configuration": {
          "dataVersion": "1.0",
          "compressionMode": "None",
          "overwriteMode": true
        }
      }
    }
  }
}
EOF
)
    
    echo "🚀 Creating billing export..."
    
    # Create the export
    EXPORT_RESPONSE=$(az rest --method PUT \
        --uri "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$CSP_BILLING_ACCOUNT_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME?api-version=2023-11-01" \
        --body "$EXPORT_BODY" 2>&1)
    
    if [[ "$EXPORT_RESPONSE" == *"error"* ]]; then
        echo -e "${YELLOW}⚠️  Export might already exist or there was an error. Checking status...${NC}"
        
        # Check if export exists
        EXISTING_CHECK=$(az rest --method GET \
            --uri "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$CSP_BILLING_ACCOUNT_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME?api-version=2023-11-01" 2>&1)
        
        if [[ "$EXISTING_CHECK" != *"error"* ]]; then
            echo -e "${GREEN}✅ Export '$EXPORT_NAME' already exists${NC}"
        else
            echo -e "${RED}❌ Failed to create export. Error details:${NC}"
            echo "$EXPORT_RESPONSE"
            echo ""
            echo "You may need to create the export manually in the Azure Portal."
        fi
    else
        echo -e "${GREEN}✅ Billing export created successfully${NC}"
        
        # Trigger immediate export run
        echo "🔄 Triggering immediate export execution..."
        az rest --method POST \
            --uri "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$CSP_BILLING_ACCOUNT_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME/run?api-version=2023-11-01" \
            --output none 2>/dev/null || echo "   Note: Manual trigger may not be available immediately"
    fi
fi

# ===========================
# STEP 9: CREATE SYNAPSE WORKSPACE
# ===========================
echo ""
echo -e "${YELLOW}Step 9: Creating Synapse Analytics Workspace${NC}"
echo "--------------------------------------"

# Check if Synapse workspace already exists
SYNAPSE_EXISTS=$(az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$RESOURCE_GROUP" --query name -o tsv 2>/dev/null)

if [ -n "$SYNAPSE_EXISTS" ]; then
    echo -e "${YELLOW}⚠️  Synapse workspace '$SYNAPSE_WORKSPACE' already exists${NC}"
    SYNAPSE_STORAGE=$(az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$RESOURCE_GROUP" --query "defaultDataLakeStorage.accountUrl" -o tsv | sed 's/https:\/\///' | sed 's/.dfs.core.windows.net\///')
else
    # Create storage for Synapse
    SYNAPSE_STORAGE="synapse$(date +%s)"
    echo "📦 Creating Synapse storage account: $SYNAPSE_STORAGE..."
    
    az storage account create \
        --name "$SYNAPSE_STORAGE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --enable-hierarchical-namespace true \
        --output none
    
    # Create file system for Synapse
    az storage fs create \
        --name "synapsefs" \
        --account-name "$SYNAPSE_STORAGE" \
        --auth-mode login \
        --output none
    
    # Create Synapse workspace
    echo "🏗️ Creating Synapse workspace: $SYNAPSE_WORKSPACE..."
    echo "   This may take 5-10 minutes..."
    
    az synapse workspace create \
        --name "$SYNAPSE_WORKSPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$SYNAPSE_STORAGE" \
        --file-system "synapsefs" \
        --sql-admin-login-user "sqladmin" \
        --sql-admin-login-password "CSPBilling2024!" \
        --location "$LOCATION" \
        --output none
    
    echo -e "${GREEN}✅ Synapse workspace created${NC}"
    
    # Configure firewall
    echo "🔒 Configuring Synapse firewall..."
    
    # Allow Azure services
    az synapse workspace firewall-rule create \
        --name "AllowAllWindowsAzureIps" \
        --workspace-name "$SYNAPSE_WORKSPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --start-ip-address "0.0.0.0" \
        --end-ip-address "0.0.0.0" \
        --output none
    
    # Allow current client IP
    CLIENT_IP=$(curl -s https://api.ipify.org)
    az synapse workspace firewall-rule create \
        --name "AllowClientIp" \
        --workspace-name "$SYNAPSE_WORKSPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --start-ip-address "$CLIENT_IP" \
        --end-ip-address "$CLIENT_IP" \
        --output none 2>/dev/null || echo "   Note: Could not add client IP automatically"
fi

# ===========================
# STEP 10: CONFIGURE SYNAPSE FOR FOCUS
# ===========================
echo ""
echo -e "${YELLOW}Step 10: Configuring Synapse for FOCUS Billing Data${NC}"
echo "--------------------------------------"

# Generate SQL script for FOCUS format
cat > synapse_focus_setup.sql <<EOF
-- ====================================================================================================
-- Synapse Setup for CSP Billing with FOCUS Format
-- ====================================================================================================

-- Create database if not exists
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics')
BEGIN
    CREATE DATABASE BillingAnalytics
END
GO

USE BillingAnalytics
GO

-- Drop existing views to recreate
DROP VIEW IF EXISTS CSPBillingFOCUS;
DROP VIEW IF EXISTS BillingSummary;
GO

-- ====================================================================================================
-- Main view for FOCUS format billing data
-- FOCUS (FinOps Open Cost and Usage Specification) provides standardized cloud cost data
-- ====================================================================================================
CREATE VIEW CSPBillingFOCUS AS
SELECT *
FROM OPENROWSET(
    BULK 'https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/$ROOT_FOLDER/*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS FOCUSData
GO

-- ====================================================================================================
-- Summary view for quick insights
-- ====================================================================================================
CREATE VIEW BillingSummary AS
SELECT 
    -- FOCUS standard dimensions
    BillingPeriodStart,
    BillingPeriodEnd,
    InvoiceIssuerName,
    ProviderName,
    ServiceName,
    ServiceCategory,
    Region,
    ResourceId,
    ResourceName,
    ResourceType,
    
    -- Customer information (CSP specific)
    SubAccountId as CustomerTenantId,
    SubAccountName as CustomerName,
    
    -- Cost metrics
    BilledCost,
    BillingCurrency,
    ContractedCost,
    EffectiveCost,
    ListCost,
    
    -- Usage metrics
    UsageQuantity,
    UsageUnit,
    
    -- Additional metadata
    ChargeCategory,
    ChargeFrequency,
    ChargeType,
    CommitmentDiscountId,
    PricingCategory,
    Tags
FROM CSPBillingFOCUS
WHERE BillingPeriodStart >= DATEADD(day, -30, GETDATE())
GO

-- ====================================================================================================
-- Query examples for FOCUS data
-- ====================================================================================================

-- Example 1: Total cost by customer (last 30 days)
/*
SELECT 
    SubAccountName as CustomerName,
    SubAccountId as CustomerTenantId,
    BillingCurrency,
    SUM(BilledCost) as TotalBilledCost,
    SUM(EffectiveCost) as TotalEffectiveCost,
    COUNT(DISTINCT ResourceId) as ResourceCount
FROM CSPBillingFOCUS
WHERE BillingPeriodStart >= DATEADD(day, -30, GETDATE())
GROUP BY SubAccountName, SubAccountId, BillingCurrency
ORDER BY TotalBilledCost DESC
*/

-- Example 2: Cost by service category
/*
SELECT 
    ServiceCategory,
    ServiceName,
    SUM(BilledCost) as TotalCost,
    COUNT(DISTINCT SubAccountId) as CustomerCount,
    COUNT(DISTINCT ResourceId) as ResourceCount
FROM CSPBillingFOCUS
WHERE BillingPeriodStart >= DATEADD(day, -30, GETDATE())
GROUP BY ServiceCategory, ServiceName
ORDER BY TotalCost DESC
*/

-- Example 3: Daily cost trend
/*
SELECT 
    CAST(BillingPeriodStart as DATE) as Date,
    SUM(BilledCost) as DailyCost,
    COUNT(DISTINCT SubAccountId) as ActiveCustomers
FROM CSPBillingFOCUS
WHERE BillingPeriodStart >= DATEADD(day, -30, GETDATE())
GROUP BY CAST(BillingPeriodStart as DATE)
ORDER BY Date DESC
*/

PRINT 'FOCUS billing views created successfully!'
PRINT 'Storage path: https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/$ROOT_FOLDER/'
PRINT ''
PRINT 'Note: FOCUS format provides standardized column names across all cloud providers.'
PRINT 'Key columns include: BilledCost, EffectiveCost, ServiceName, ResourceId, SubAccountId (Customer)'
GO
EOF

echo "📝 SQL setup script created: synapse_focus_setup.sql"

# Assign Storage Blob Data Reader permission on storage account
echo "🔐 Assigning Storage Blob Data Reader on storage account..."
STORAGE_RESOURCE_ID="/subscriptions/$MGMT_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME"
az role assignment create \
    --assignee "$APP_ID" \
    --role "Storage Blob Data Reader" \
    --scope "$STORAGE_RESOURCE_ID" \
    --only-show-errors 2>/dev/null || echo "   Note: Permission might already exist"

# Assign Synapse Administrator role
echo "🔐 Assigning Synapse Administrator role..."
az synapse role assignment create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --role "Synapse Administrator" \
    --assignee "$APP_ID" \
    --only-show-errors 2>/dev/null || echo "   Note: Role might already exist"

# ===========================
# STEP 11: SAVE CONFIGURATION & QUERY FILES
# ===========================
echo ""
echo -e "${YELLOW}Step 11: Saving Configuration and Query Files${NC}"
echo "--------------------------------------"

# Save Python configuration for remote queries
cat > synapse_config.py <<EOF
# Auto-generated Synapse configuration for CSP Billing
# Created: $(date)

SYNAPSE_CONFIG = {
    'tenant_id': '$TENANT_ID',
    'client_id': '$APP_ID',
    'client_secret': '$CLIENT_SECRET',
    'workspace_name': '$SYNAPSE_WORKSPACE',
    'database_name': 'BillingAnalytics',
    'storage_account': '$STORAGE_ACCOUNT_NAME',
    'container': '$CONTAINER_NAME',
    'export_path': '$ROOT_FOLDER',
    'resource_group': '$RESOURCE_GROUP',
    'subscription_id': '$MGMT_SUBSCRIPTION_ID',
    'csp_billing_account_id': '$CSP_BILLING_ACCOUNT_ID',
    'export_format': 'FOCUS'
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
print(f"  Export Format: {SYNAPSE_CONFIG['export_format']}")
EOF

echo -e "${GREEN}✅ Python configuration saved to: synapse_config.py${NC}"

# Create FOCUS-specific billing queries
cat > billing_queries_focus.sql <<EOF
-- ========================================================
-- CSP BILLING QUERIES FOR FOCUS FORMAT
-- ========================================================
-- FOCUS (FinOps Open Cost and Usage Specification) provides
-- standardized column names across all cloud providers
-- ========================================================

-- 1. Total cost by customer (last 30 days)
SELECT 
    SubAccountName as CustomerName,
    SubAccountId as CustomerTenantId,
    BillingCurrency,
    SUM(BilledCost) as TotalBilledCost,
    SUM(EffectiveCost) as TotalEffectiveCost,
    COUNT(DISTINCT ResourceId) as ResourceCount
FROM CSPBillingFOCUS
WHERE BillingPeriodStart >= DATEADD(day, -30, GETDATE())
GROUP BY SubAccountName, SubAccountId, BillingCurrency
ORDER BY TotalBilledCost DESC;

-- 2. Daily cost trend for all customers
SELECT 
    CAST(BillingPeriodStart as DATE) as Date,
    SUM(BilledCost) as DailyCost,
    SUM(EffectiveCost) as DailyEffectiveCost,
    COUNT(DISTINCT SubAccountId) as ActiveCustomers,
    COUNT(DISTINCT ResourceId) as ActiveResources
FROM CSPBillingFOCUS
WHERE BillingPeriodStart >= DATEADD(day, -30, GETDATE())
GROUP BY CAST(BillingPeriodStart as DATE)
ORDER BY Date DESC;

-- 3. Cost by service category across all customers
SELECT 
    ServiceCategory,
    ServiceName,
    SUM(BilledCost) as TotalCost,
    COUNT(DISTINCT SubAccountId) as CustomerCount,
    COUNT(DISTINCT ResourceId) as ResourceCount
FROM CSPBillingFOCUS
WHERE BillingPeriodStart >= DATEADD(day, -30, GETDATE())
GROUP BY ServiceCategory, ServiceName
ORDER BY TotalCost DESC;

-- 4. Top 10 customers by spend
SELECT TOP 10
    SubAccountName as CustomerName,
    SubAccountId as CustomerTenantId,
    SUM(BilledCost) as TotalCost,
    SUM(EffectiveCost) as EffectiveCost,
    COUNT(DISTINCT ServiceName) as ServicesUsed,
    COUNT(DISTINCT ResourceId) as ResourceCount
FROM CSPBillingFOCUS
WHERE BillingPeriodStart >= DATEADD(day, -30, GETDATE())
GROUP BY SubAccountName, SubAccountId
ORDER BY TotalCost DESC;

-- 5. Cost by region for all customers
SELECT 
    Region,
    COUNT(DISTINCT SubAccountId) as CustomerCount,
    SUM(BilledCost) as TotalCost,
    COUNT(DISTINCT ResourceId) as ResourceCount
FROM CSPBillingFOCUS
WHERE BillingPeriodStart >= DATEADD(day, -30, GETDATE())
    AND Region IS NOT NULL
GROUP BY Region
ORDER BY TotalCost DESC;

-- 6. Customer-specific deep dive (replace 'CUSTOMER_TENANT_ID')
SELECT 
    ServiceCategory,
    ServiceName,
    ResourceName,
    ResourceType,
    Region,
    SUM(BilledCost) as TotalCost,
    SUM(UsageQuantity) as TotalUsage,
    UsageUnit
FROM CSPBillingFOCUS
WHERE SubAccountId = 'CUSTOMER_TENANT_ID'  -- Replace with actual tenant ID
    AND BillingPeriodStart >= DATEADD(day, -30, GETDATE())
GROUP BY ServiceCategory, ServiceName, ResourceName, ResourceType, Region, UsageUnit
ORDER BY TotalCost DESC;

-- 7. Discount analysis
SELECT 
    SubAccountName as CustomerName,
    SUM(ListCost) as TotalListCost,
    SUM(ContractedCost) as TotalContractedCost,
    SUM(EffectiveCost) as TotalEffectiveCost,
    SUM(ListCost - EffectiveCost) as TotalSavings,
    CASE 
        WHEN SUM(ListCost) > 0 
        THEN ((SUM(ListCost) - SUM(EffectiveCost)) / SUM(ListCost) * 100)
        ELSE 0 
    END as DiscountPercentage
FROM CSPBillingFOCUS
WHERE BillingPeriodStart >= DATEADD(day, -30, GETDATE())
GROUP BY SubAccountName
ORDER BY TotalSavings DESC;

-- 8. Month-over-month comparison
WITH CurrentMonth AS (
    SELECT 
        SubAccountName as CustomerName,
        SUM(BilledCost) as CurrentCost
    FROM CSPBillingFOCUS
    WHERE MONTH(BillingPeriodStart) = MONTH(GETDATE())
        AND YEAR(BillingPeriodStart) = YEAR(GETDATE())
    GROUP BY SubAccountName
),
PreviousMonth AS (
    SELECT 
        SubAccountName as CustomerName,
        SUM(BilledCost) as PreviousCost
    FROM CSPBillingFOCUS
    WHERE MONTH(BillingPeriodStart) = MONTH(DATEADD(month, -1, GETDATE()))
        AND YEAR(BillingPeriodStart) = YEAR(DATEADD(month, -1, GETDATE()))
    GROUP BY SubAccountName
)
SELECT 
    COALESCE(c.CustomerName, p.CustomerName) as CustomerName,
    ISNULL(p.PreviousCost, 0) as LastMonthCost,
    ISNULL(c.CurrentCost, 0) as ThisMonthCost,
    ISNULL(c.CurrentCost, 0) - ISNULL(p.PreviousCost, 0) as CostChange,
    CASE 
        WHEN p.PreviousCost > 0 
        THEN ((c.CurrentCost - p.PreviousCost) / p.PreviousCost * 100)
        ELSE 0 
    END as PercentChange
FROM CurrentMonth c
FULL OUTER JOIN PreviousMonth p ON c.CustomerName = p.CustomerName
ORDER BY ThisMonthCost DESC;

-- 9. Untagged resources report
SELECT 
    SubAccountName as CustomerName,
    ResourceId,
    ResourceName,
    ServiceName,
    SUM(BilledCost) as Cost
FROM CSPBillingFOCUS
WHERE (Tags IS NULL OR Tags = '{}' OR Tags = '')
    AND BillingPeriodStart >= DATEADD(day, -30, GETDATE())
GROUP BY SubAccountName, ResourceId, ResourceName, ServiceName
ORDER BY Cost DESC;

-- 10. Commitment utilization (Reserved Instances, Savings Plans)
SELECT 
    CommitmentDiscountId,
    ChargeCategory,
    PricingCategory,
    SUM(BilledCost) as CommitmentCost,
    SUM(EffectiveCost) as EffectiveCommitmentCost,
    COUNT(DISTINCT SubAccountId) as CustomersUsing
FROM CSPBillingFOCUS
WHERE CommitmentDiscountId IS NOT NULL
    AND BillingPeriodStart >= DATEADD(day, -30, GETDATE())
GROUP BY CommitmentDiscountId, ChargeCategory, PricingCategory
ORDER BY CommitmentCost DESC;
EOF

echo -e "${GREEN}✅ FOCUS billing queries saved to: billing_queries_focus.sql${NC}"

# Create CSP-specific remote query client
cat > csp_remote_query_client.py <<EOF
#!/usr/bin/env python3
"""
CSP Billing Remote Query Client for FOCUS Format
Executes queries on Azure Synapse Analytics for CSP billing data
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from synapse_remote_query_client import SynapseAPIClient
import pandas as pd
from datetime import datetime, timedelta

class CSPBillingClient(SynapseAPIClient):
    """Extended client for CSP-specific billing queries with FOCUS format"""
    
    def get_customer_summary(self, days_back=30):
        """Get summary of all customers"""
        query = f"""
        SELECT 
            SubAccountName as CustomerName,
            SubAccountId as CustomerTenantId,
            SUM(BilledCost) as TotalCost,
            SUM(EffectiveCost) as EffectiveCost,
            COUNT(DISTINCT ServiceName) as ServicesUsed,
            COUNT(DISTINCT ResourceId) as ResourceCount
        FROM CSPBillingFOCUS
        WHERE BillingPeriodStart >= DATEADD(day, -{days_back}, GETDATE())
        GROUP BY SubAccountName, SubAccountId
        ORDER BY TotalCost DESC
        """
        return self.execute_query_odbc(query)
    
    def get_customer_trend(self, customer_tenant_id, days_back=30):
        """Get daily trend for specific customer"""
        query = f"""
        SELECT 
            CAST(BillingPeriodStart as DATE) as Date,
            SUM(BilledCost) as DailyCost,
            COUNT(DISTINCT ServiceName) as ServicesUsed
        FROM CSPBillingFOCUS
        WHERE SubAccountId = '{customer_tenant_id}'
            AND BillingPeriodStart >= DATEADD(day, -{days_back}, GETDATE())
        GROUP BY CAST(BillingPeriodStart as DATE)
        ORDER BY Date DESC
        """
        return self.execute_query_odbc(query)
    
    def get_service_breakdown(self):
        """Get cost breakdown by service across all customers"""
        query = """
        SELECT 
            ServiceCategory,
            ServiceName,
            SUM(BilledCost) as TotalCost,
            COUNT(DISTINCT SubAccountId) as CustomerCount
        FROM CSPBillingFOCUS
        WHERE BillingPeriodStart >= DATEADD(day, -30, GETDATE())
        GROUP BY ServiceCategory, ServiceName
        ORDER BY TotalCost DESC
        """
        return self.execute_query_odbc(query)

if __name__ == "__main__":
    # Load configuration
    from synapse_config import SYNAPSE_CONFIG
    
    # Initialize client
    client = CSPBillingClient(**SYNAPSE_CONFIG)
    
    # Get customer summary
    print("\\nCSP Customer Summary (Last 30 Days):")
    print("-" * 60)
    customers = client.get_customer_summary()
    if customers is not None:
        print(customers)
    
    # Get service breakdown
    print("\\nService Cost Breakdown:")
    print("-" * 60)
    services = client.get_service_breakdown()
    if services is not None:
        print(services.head(10))
EOF

echo -e "${GREEN}✅ CSP remote query client saved to: csp_remote_query_client.py${NC}"

cat > csp_billing_config.json <<EOF
{
  "deployment_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "csp_billing": {
    "account_id": "$CSP_BILLING_ACCOUNT_ID",
    "account_name": "$CSP_BILLING_ACCOUNT_NAME"
  },
  "management_subscription": {
    "id": "$MGMT_SUBSCRIPTION_ID",
    "name": "$MGMT_SUBSCRIPTION_NAME"
  },
  "resource_group": "$RESOURCE_GROUP",
  "location": "$LOCATION",
  "billing_export": {
    "name": "$EXPORT_NAME",
    "format": "FOCUS",
    "version": "1.0",
    "compression": "None",
    "overwrite": true,
    "schedule": "Daily"
  },
  "storage": {
    "account_name": "$STORAGE_ACCOUNT_NAME",
    "container": "$CONTAINER_NAME",
    "root_folder": "$ROOT_FOLDER",
    "full_path": "https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/$ROOT_FOLDER/"
  },
  "synapse": {
    "workspace": "$SYNAPSE_WORKSPACE",
    "endpoint": "$SYNAPSE_WORKSPACE.sql.azuresynapse.net",
    "database": "BillingAnalytics",
    "admin_user": "sqladmin",
    "storage_account": "$SYNAPSE_STORAGE"
  }
}
EOF

echo -e "${GREEN}✅ Configuration saved to: csp_billing_config.json${NC}"

# ===========================
# SUMMARY
# ===========================
echo ""
echo -e "${GREEN}=====================================================================================================${NC}"
echo -e "${GREEN}                                    DEPLOYMENT COMPLETE                                             ${NC}"
echo -e "${GREEN}=====================================================================================================${NC}"
echo ""
echo "📋 CSP Billing Account: $CSP_BILLING_ACCOUNT_NAME"
echo "📁 Resource Group: $RESOURCE_GROUP"
echo "📦 Storage Account: $STORAGE_ACCOUNT_NAME"
echo "📊 Synapse Workspace: $SYNAPSE_WORKSPACE"
echo "📅 Export Schedule: Daily with overwrite (FOCUS format)"
echo "🔐 Service Principal: $APP_DISPLAY_NAME (App ID: $APP_ID)"
echo ""
echo -e "${YELLOW}Files Created:${NC}"
echo "  📄 synapse_config.py - Python configuration for remote queries"
echo "  📄 synapse_focus_setup.sql - SQL script to create Synapse views"
echo "  📄 billing_queries_focus.sql - Ready-to-use FOCUS billing queries"
echo "  📄 csp_remote_query_client.py - Python client for CSP queries"
echo "  📄 csp_billing_config.json - Complete deployment configuration"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Wait for first export to complete (can take up to 24 hours)"
echo "2. Open Synapse Studio: https://web.azuresynapse.net"
echo "3. Run the SQL script from: synapse_focus_setup.sql"
echo "4. Test remote queries: python3 csp_remote_query_client.py"
echo ""
echo -e "${BLUE}Remote Query Usage:${NC}"
echo "# Using the existing client:"
echo "python3 synapse_remote_query_client.py"
echo ""
echo "# Using CSP-specific client:"
echo "python3 csp_remote_query_client.py"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo "# Check export status:"
echo "az rest --method GET --uri \"https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$CSP_BILLING_ACCOUNT_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME?api-version=2023-11-01\" --query \"properties.nextRunTimeEstimate\""
echo ""
echo "# List files in storage:"
echo "az storage blob list --account-name $STORAGE_ACCOUNT_NAME --container-name $CONTAINER_NAME --prefix \"$ROOT_FOLDER\" --auth-mode login"
echo ""
echo "# Test Synapse connection:"
echo "python3 test_synapse_connection.py"
echo ""
echo -e "${GREEN}Setup complete! Your CSP billing analytics platform is ready.${NC}"
echo -e "${GREEN}The system maintains full compatibility with synapse_remote_query_client.py${NC}"