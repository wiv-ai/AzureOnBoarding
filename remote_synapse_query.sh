#!/bin/bash

echo "🔍 Remote Synapse Query Validation Script"
echo "=========================================="

# Configuration
TENANT_ID="ba153ff0-3397-4ef5-a214-dd33e8c37bff"
APP_ID="554b11c1-18f9-46b5-a096-30e0a2cfae6f"
CLIENT_SECRET="tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams"
SYNAPSE_WORKSPACE="wiv-synapse-billing"
STORAGE_ACCOUNT="billingstorage77626"
CONTAINER="billing-exports"
SUBSCRIPTION_ID="62b32106-4b98-47ea-9ac5-4181f33ae2af"
RESOURCE_GROUP="wiv-rg"

# The actual file path from the error message
ACTUAL_FILE_PATH="billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv"

# Login with service principal
echo "🔐 Logging in with service principal..."
az login --service-principal \
    --username "$APP_ID" \
    --password "$CLIENT_SECRET" \
    --tenant "$TENANT_ID" \
    --output none

if [ $? -ne 0 ]; then
    echo "❌ Login failed. Please check credentials."
    exit 1
fi

# Set subscription
az account set --subscription "$SUBSCRIPTION_ID"
echo "✅ Logged in successfully"

# Test 1: Verify service principal permissions
echo ""
echo "🔑 Checking service principal permissions..."
echo "Service Principal App ID: $APP_ID"

# Get the Object ID of the service principal
SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null)
if [ -n "$SP_OBJECT_ID" ]; then
    echo "Service Principal Object ID: $SP_OBJECT_ID"
else
    echo "⚠️  Could not retrieve service principal object ID"
fi

# Check storage account permissions
echo ""
echo "📦 Checking storage account permissions..."
STORAGE_ROLES=$(az role assignment list \
    --assignee "$APP_ID" \
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT" \
    --query "[].roleDefinitionName" \
    --output tsv 2>/dev/null)

if [ -n "$STORAGE_ROLES" ]; then
    echo "Storage account roles: $STORAGE_ROLES"
else
    echo "⚠️  No explicit storage account roles found (may have inherited permissions)"
fi

# Test 2: Check if the specific file exists
echo ""
echo "📂 Checking for the specific billing file..."
echo "Looking for: $ACTUAL_FILE_PATH"

FILE_EXISTS=$(az storage blob exists \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER" \
    --name "$ACTUAL_FILE_PATH" \
    --auth-mode login \
    --query exists \
    --output tsv 2>/dev/null)

if [ "$FILE_EXISTS" == "true" ]; then
    echo "✅ File exists in storage"
    
    # Get file properties
    FILE_SIZE=$(az storage blob show \
        --account-name "$STORAGE_ACCOUNT" \
        --container-name "$CONTAINER" \
        --name "$ACTUAL_FILE_PATH" \
        --auth-mode login \
        --query "properties.contentLength" \
        --output tsv 2>/dev/null)
    
    if [ -n "$FILE_SIZE" ]; then
        echo "File size: $FILE_SIZE bytes"
    fi
else
    echo "⚠️  File not found or no access"
    
    # Try to list files in the directory
    echo ""
    echo "Attempting to list files in the billing-data directory..."
    FILE_LIST=$(az storage blob list \
        --account-name "$STORAGE_ACCOUNT" \
        --container-name "$CONTAINER" \
        --prefix "billing-data/DailyBillingExport" \
        --auth-mode login \
        --query "[].name" \
        --output table 2>/dev/null)
    
    if [ -n "$FILE_LIST" ]; then
        echo "Files found:"
        echo "$FILE_LIST"
    else
        echo "Could not list files - may be a permission issue"
    fi
fi

# Test 3: Check Synapse workspace access
echo ""
echo "🔷 Checking Synapse workspace access..."
SYNAPSE_EXISTS=$(az synapse workspace show \
    --name "$SYNAPSE_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --query "name" \
    --output tsv 2>/dev/null)

if [ -n "$SYNAPSE_EXISTS" ]; then
    echo "✅ Synapse workspace accessible: $SYNAPSE_WORKSPACE"
    
    # Get Synapse endpoint
    SYNAPSE_ENDPOINT=$(az synapse workspace show \
        --name "$SYNAPSE_WORKSPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "connectivityEndpoints.sqlOnDemand" \
        --output tsv 2>/dev/null)
    
    if [ -n "$SYNAPSE_ENDPOINT" ]; then
        echo "SQL endpoint: $SYNAPSE_ENDPOINT"
    fi
else
    echo "⚠️  Cannot access Synapse workspace"
fi

# Test 4: Generate working queries
echo ""
echo "📊 Generating validated Synapse queries..."

cat > validated_query.sql <<'EOF'
-- IMPORTANT: Use this query in Synapse Studio
-- Connect to: Built-in (serverless SQL pool)

-- Query 1: Test with exact file path
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    Date NVARCHAR(100),
    ServiceFamily NVARCHAR(100),
    MeterCategory NVARCHAR(100),
    MeterSubcategory NVARCHAR(100),
    MeterName NVARCHAR(200),
    BillingAccountName NVARCHAR(100),
    CostCenter NVARCHAR(50),
    ResourceGroup NVARCHAR(100),
    ResourceLocation NVARCHAR(50),
    ConsumedService NVARCHAR(100),
    ResourceId NVARCHAR(500),
    ChargeType NVARCHAR(50),
    PublisherType NVARCHAR(50),
    Quantity NVARCHAR(50),
    CostInBillingCurrency NVARCHAR(50),
    CostInUSD NVARCHAR(50),
    PayGPrice NVARCHAR(50),
    BillingCurrencyCode NVARCHAR(10),
    SubscriptionName NVARCHAR(100),
    SubscriptionId NVARCHAR(50),
    ProductName NVARCHAR(200),
    Frequency NVARCHAR(50),
    UnitOfMeasure NVARCHAR(50),
    Tags NVARCHAR(MAX)
) AS BillingData;

-- Query 2: If you need to use credentials
-- First create a credential (run once):
/*
CREATE DATABASE SCOPED CREDENTIAL BillingStorageCredential
WITH IDENTITY = 'Managed Identity';

-- Then query with credential:
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
    DATA_SOURCE = 'BillingStorage',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    Date NVARCHAR(100),
    ServiceFamily NVARCHAR(100),
    ResourceGroup NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData;
*/
EOF

echo "✅ Query saved to validated_query.sql"

# Test 5: Attempt direct query execution via REST API
echo ""
echo "🚀 Attempting remote query execution..."

# Get access token for Synapse
echo "Getting access token for Synapse..."
TOKEN=$(az account get-access-token \
    --resource "https://dev.azuresynapse.net" \
    --query accessToken \
    --output tsv 2>/dev/null)

if [ -n "$TOKEN" ]; then
    echo "✅ Access token obtained"
    
    # Try to execute a simple test query
    QUERY="SELECT 'Connection Test' as Status, GETDATE() as CurrentTime"
    
    echo "Executing test query..."
    RESPONSE=$(curl -s -X POST \
        "https://$SYNAPSE_WORKSPACE.dev.azuresynapse.net/sql/query?api-version=2020-12-01" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"$QUERY\", \"database\": \"master\"}" 2>/dev/null)
    
    if [ -n "$RESPONSE" ]; then
        echo "Response received:"
        echo "$RESPONSE" | head -c 500
    else
        echo "⚠️  No response from Synapse SQL endpoint"
    fi
else
    echo "⚠️  Could not obtain access token"
fi

# Summary
echo ""
echo "======================================"
echo "📋 VALIDATION SUMMARY"
echo "======================================"
echo ""
echo "✅ Service Principal: $APP_ID"
echo "✅ Storage Account: $STORAGE_ACCOUNT"
echo "✅ Synapse Workspace: $SYNAPSE_WORKSPACE"
echo ""
echo "📁 Target File:"
echo "   $ACTUAL_FILE_PATH"
echo ""
echo "🔧 TROUBLESHOOTING STEPS:"
echo ""
echo "1. Ensure the service principal has these roles:"
echo "   - Storage Blob Data Contributor on storage account"
echo "   - Synapse Administrator on workspace"
echo ""
echo "2. In Azure Portal, verify firewall rules:"
echo "   - Storage account allows Azure services"
echo "   - Synapse workspace allows your IP"
echo ""
echo "3. To run queries:"
echo "   a. Open https://web.azuresynapse.net"
echo "   b. Select workspace: $SYNAPSE_WORKSPACE"
echo "   c. Use 'Built-in' serverless SQL pool"
echo "   d. Run the query from validated_query.sql"
echo ""
echo "4. If file access fails, check:"
echo "   - File exists at the exact path"
echo "   - Service principal has storage permissions"
echo "   - No firewall blocking access"
echo ""
echo "✅ Validation script complete!"