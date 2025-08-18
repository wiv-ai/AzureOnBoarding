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
# STEP 1: LOGIN & DISCOVERY
# ===========================
echo -e "${YELLOW}Step 1: Authentication and CSP Billing Account Discovery${NC}"
echo "--------------------------------------"

# Login to Azure
echo "🔐 Logging into Azure..."
az login --output none

# ===========================
# DISCOVER CSP BILLING ACCOUNT
# ===========================
echo ""
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
# GET MANAGEMENT SUBSCRIPTION
# ===========================
echo ""
echo -e "${YELLOW}Step 2: Select Management Subscription for Resources${NC}"
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
# CHECK EXISTING RESOURCES
# ===========================
echo ""
echo -e "${YELLOW}Step 3: Check for Existing Resources${NC}"
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
# GATHER CONFIGURATION
# ===========================
echo ""
echo -e "${YELLOW}Step 4: Configuration Settings${NC}"
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
# CREATE RESOURCES
# ===========================
echo ""
echo -e "${YELLOW}Step 5: Creating Resources in Management Subscription${NC}"
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
# CREATE BILLING EXPORT
# ===========================
if [ "$SKIP_EXPORT_CREATION" == "false" ]; then
    echo ""
    echo -e "${YELLOW}Step 6: Creating CSP Billing Export (FOCUS Format)${NC}"
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
# CREATE SYNAPSE WORKSPACE
# ===========================
echo ""
echo -e "${YELLOW}Step 7: Creating Synapse Analytics Workspace${NC}"
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
# CONFIGURE SYNAPSE FOR FOCUS
# ===========================
echo ""
echo -e "${YELLOW}Step 8: Configuring Synapse for FOCUS Billing Data${NC}"
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
echo ""
echo "To execute this script:"
echo "1. Open Synapse Studio: https://web.azuresynapse.net"
echo "2. Select workspace: $SYNAPSE_WORKSPACE"
echo "3. Go to 'Develop' → 'SQL scripts' → 'New SQL script'"
echo "4. Copy the contents of synapse_focus_setup.sql"
echo "5. Run the script"

# ===========================
# SAVE CONFIGURATION
# ===========================
echo ""
echo -e "${YELLOW}Step 9: Saving Configuration${NC}"
echo "--------------------------------------"

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
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Wait for first export to complete (can take up to 24 hours)"
echo "2. Open Synapse Studio: https://web.azuresynapse.net"
echo "3. Run the SQL script from: synapse_focus_setup.sql"
echo "4. Query your CSP billing data using FOCUS standard columns"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo "# Check export status:"
echo "az rest --method GET --uri \"https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$CSP_BILLING_ACCOUNT_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME?api-version=2023-11-01\" --query \"properties.nextRunTimeEstimate\""
echo ""
echo "# List files in storage:"
echo "az storage blob list --account-name $STORAGE_ACCOUNT_NAME --container-name $CONTAINER_NAME --prefix \"$ROOT_FOLDER\" --auth-mode login"
echo ""
echo -e "${GREEN}Setup complete! Your CSP billing analytics platform is ready.${NC}"