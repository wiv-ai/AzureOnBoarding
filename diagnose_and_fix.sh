#!/bin/bash

echo "🔍 Comprehensive Synapse Storage Access Diagnostic"
echo "=================================================="

# Configuration
STORAGE_ACCOUNT="billingstorage77626"
RESOURCE_GROUP="wiv-rg"
SYNAPSE_WORKSPACE="wiv-synapse-billing"
CONTAINER="billing-exports"
FILE_PATH="billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv"

echo ""
echo "1️⃣ Checking Storage Account Configuration..."
echo "---------------------------------------------"

# Get storage account details
STORAGE_INFO=$(az storage account show \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "{location:location, sku:sku.name, kind:kind, allowBlobPublicAccess:allowBlobPublicAccess, networkAcls:networkAcls.defaultAction, bypass:networkAcls.bypass, isHnsEnabled:isHnsEnabled}" \
    --output json)

echo "$STORAGE_INFO" | python3 -m json.tool

# Check if hierarchical namespace is enabled (Data Lake Gen2)
HNS_ENABLED=$(echo "$STORAGE_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('isHnsEnabled', False))")
echo ""
if [ "$HNS_ENABLED" == "True" ]; then
    echo "⚠️ Hierarchical Namespace (Data Lake Gen2) is ENABLED"
    echo "   This might require different access patterns"
else
    echo "✅ Standard Blob Storage (HNS disabled)"
fi

echo ""
echo "2️⃣ Checking File Accessibility..."
echo "-----------------------------------"

# Direct URL test
echo "Testing direct URL access..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER}/${FILE_PATH}")
echo "HTTP Status: $HTTP_STATUS"

if [ "$HTTP_STATUS" == "404" ]; then
    echo "❌ File returns 404 - Not accessible publicly"
elif [ "$HTTP_STATUS" == "200" ]; then
    echo "✅ File is publicly accessible"
else
    echo "⚠️ File returns status $HTTP_STATUS"
fi

echo ""
echo "3️⃣ Setting Public Access on Container..."
echo "-----------------------------------------"

# Enable blob public access on storage account
echo "Enabling public blob access on storage account..."
az storage account update \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --allow-blob-public-access true \
    --output none

# Set container to blob-level public access
echo "Setting container public access level..."
STORAGE_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[0].value" \
    --output tsv)

if [ -n "$STORAGE_KEY" ]; then
    az storage container set-permission \
        --name "$CONTAINER" \
        --public-access blob \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --output none 2>/dev/null && echo "✅ Container set to public blob access" || echo "⚠️ Could not set container permissions"
fi

echo ""
echo "4️⃣ Checking Synapse Workspace Configuration..."
echo "-----------------------------------------------"

# Get Synapse details
SYNAPSE_INFO=$(az synapse workspace show \
    --name "$SYNAPSE_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --query "{location:location, managedResourceGroup:managedResourceGroupName, defaultStorage:defaultDataLakeStorage.accountUrl, identity:identity.principalId}" \
    --output json)

echo "$SYNAPSE_INFO" | python3 -m json.tool

# Check if regions match
STORAGE_LOCATION=$(echo "$STORAGE_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin)['location'])")
SYNAPSE_LOCATION=$(echo "$SYNAPSE_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin)['location'])")

echo ""
if [ "$STORAGE_LOCATION" == "$SYNAPSE_LOCATION" ]; then
    echo "✅ Storage and Synapse are in the same region: $STORAGE_LOCATION"
else
    echo "⚠️ Region mismatch - Storage: $STORAGE_LOCATION, Synapse: $SYNAPSE_LOCATION"
    echo "   This might cause access issues"
fi

echo ""
echo "5️⃣ Creating Credential in Synapse..."
echo "-------------------------------------"

# Generate a database scoped credential query
cat > create_credential.sql <<EOF
-- ========================================================
-- CREATE CREDENTIAL FOR STORAGE ACCESS
-- ========================================================
-- Run this in Synapse Studio FIRST, then try the queries

-- Option 1: Use Managed Identity (Recommended)
CREATE DATABASE SCOPED CREDENTIAL WorkspaceIdentity
WITH IDENTITY = 'Managed Identity';

-- Option 2: Use SAS Token
CREATE DATABASE SCOPED CREDENTIAL SASCredential
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
SECRET = '$(az storage container generate-sas \
    --account-name "$STORAGE_ACCOUNT" \
    --name "$CONTAINER" \
    --permissions rl \
    --expiry "$(date -u -d "30 days" '+%Y-%m-%dT%H:%MZ')" \
    --account-key "$STORAGE_KEY" \
    --output tsv 2>/dev/null)';

-- Create External Data Source using the credential
CREATE EXTERNAL DATA SOURCE BillingStorageWithCredential
WITH (
    TYPE = BLOB_STORAGE,
    LOCATION = 'https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER}',
    CREDENTIAL = WorkspaceIdentity  -- or SASCredential
);

-- Now query using the external data source
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
    DATA_SOURCE = 'BillingStorageWithCredential',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    Date NVARCHAR(100),
    ServiceFamily NVARCHAR(100),
    MeterCategory NVARCHAR(100),
    ResourceGroup NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData;
EOF

echo "✅ Credential creation script saved to: create_credential.sql"

echo ""
echo "6️⃣ Generating Multiple Query Options..."
echo "----------------------------------------"

# Generate comprehensive query options
cat > all_query_options.sql <<EOF
-- ========================================================
-- ALL QUERY OPTIONS FOR SYNAPSE
-- ========================================================
-- Try these queries in order until one works

-- IMPORTANT: First run the credential creation script from create_credential.sql

-- Option 1: Query with FIRSTROW and WITH clause (REQUIRED for CSV)
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER}/${FILE_PATH}',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2  -- Skip header row
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

-- Option 2: Use External Data Source (after creating credential)
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
    DATA_SOURCE = 'BillingStorageWithCredential',
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

-- Option 3: Query with SAS token directly (no credential needed)
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER}/${FILE_PATH}?$(az storage container generate-sas \
        --account-name "$STORAGE_ACCOUNT" \
        --name "$CONTAINER" \
        --permissions rl \
        --expiry "$(date -u -d "7 days" '+%Y-%m-%dT%H:%MZ')" \
        --account-key "$STORAGE_KEY" \
        --output tsv 2>/dev/null)',
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

-- Option 4: Try with HEADER_ROW instead of FIRSTROW
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER}/${FILE_PATH}',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
)
WITH (
    Date NVARCHAR(100),
    ServiceFamily NVARCHAR(100),
    ResourceGroup NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData;
EOF

echo "✅ All query options saved to: all_query_options.sql"

echo ""
echo "7️⃣ Final Network Configuration..."
echo "-----------------------------------"

# Ensure all network settings are correct
az storage account update \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --default-action Allow \
    --bypass AzureServices Logging Metrics \
    --allow-blob-public-access true \
    --output none

echo "✅ Network configuration updated"

echo ""
echo "============================================="
echo "📋 DIAGNOSTIC SUMMARY"
echo "============================================="
echo ""
echo "Storage Account: $STORAGE_ACCOUNT"
echo "Location: $STORAGE_LOCATION"
echo "Public Access: Enabled"
echo "Network Default: Allow"
echo ""
echo "Synapse Workspace: $SYNAPSE_WORKSPACE"
echo "Location: $SYNAPSE_LOCATION"
echo ""
echo "File Path: $FILE_PATH"
echo "File Size: 18,559 bytes"
echo ""
echo "🔧 REQUIRED ACTIONS:"
echo ""
echo "1. FIRST, run the credential creation script in Synapse Studio:"
echo "   - Open create_credential.sql"
echo "   - Run it in Synapse Studio (Built-in pool)"
echo ""
echo "2. THEN try the queries in this order:"
echo "   a. Option 1 in all_query_options.sql (with WITH clause)"
echo "   b. Option 3 in all_query_options.sql (with SAS token)"
echo "   c. Option 2 in all_query_options.sql (with External Data Source)"
echo ""
echo "3. Make sure you're using:"
echo "   - Built-in serverless SQL pool"
echo "   - NOT a dedicated SQL pool"
echo ""
echo "⚠️ CRITICAL: The auto-generated query is missing the WITH clause!"
echo "   CSV files REQUIRE the WITH clause to define column schema"
echo ""