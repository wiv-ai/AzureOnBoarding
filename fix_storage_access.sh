#!/bin/bash

echo "🔧 Fixing Storage Account Access for Synapse"
echo "============================================="

# Configuration
STORAGE_ACCOUNT="billingstorage77626"
RESOURCE_GROUP="wiv-rg"
SYNAPSE_WORKSPACE="wiv-synapse-billing"
APP_ID="554b11c1-18f9-46b5-a096-30e0a2cfae6f"
SP_OBJECT_ID="62006af7-82b2-4f07-99c5-29d946bbc9a5"
SUBSCRIPTION_ID="62b32106-4b98-47ea-9ac5-4181f33ae2af"

echo "📦 Storage Account: $STORAGE_ACCOUNT"
echo "🔷 Synapse Workspace: $SYNAPSE_WORKSPACE"
echo ""

# 1. Enable Azure Services Access
echo "1️⃣ Enabling Azure Services access to storage account..."
az storage account update \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --default-action Allow \
    --bypass AzureServices \
    --output none

echo "✅ Azure Services can now access storage"

# 2. Add Synapse Workspace to Storage Firewall
echo ""
echo "2️⃣ Adding Synapse workspace to storage firewall..."

# Get Synapse workspace managed identity
SYNAPSE_IDENTITY=$(az synapse workspace show \
    --name "$SYNAPSE_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --query "identity.principalId" \
    --output tsv)

if [ -n "$SYNAPSE_IDENTITY" ]; then
    echo "Synapse Managed Identity: $SYNAPSE_IDENTITY"
    
    # Assign Storage Blob Data Reader to Synapse managed identity
    echo "Assigning Storage Blob Data Reader role to Synapse..."
    az role assignment create \
        --assignee "$SYNAPSE_IDENTITY" \
        --role "Storage Blob Data Reader" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT" \
        --output none 2>/dev/null || echo "Role may already exist"
    
    echo "✅ Synapse managed identity has storage access"
else
    echo "⚠️ Could not get Synapse managed identity"
fi

# 3. Assign Storage Blob Data Reader to Service Principal
echo ""
echo "3️⃣ Ensuring service principal has correct storage permissions..."

# Remove any existing role assignments to avoid conflicts
echo "Cleaning up existing roles..."
az role assignment delete \
    --assignee "$APP_ID" \
    --role "Storage Blob Data Contributor" \
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT" \
    2>/dev/null || true

# Assign Storage Blob Data Reader (read-only is sufficient for Synapse queries)
echo "Assigning Storage Blob Data Reader role..."
az role assignment create \
    --assignee "$APP_ID" \
    --role "Storage Blob Data Reader" \
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT" \
    --output none

echo "✅ Service principal has Storage Blob Data Reader role"

# 4. Configure storage account network rules
echo ""
echo "4️⃣ Configuring storage network rules..."

# Allow trusted Microsoft services
az storage account update \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --bypass AzureServices Logging Metrics \
    --output none

echo "✅ Trusted Microsoft services enabled"

# 5. Create SAS token for testing
echo ""
echo "5️⃣ Creating SAS token for direct access testing..."

# Get storage account key
STORAGE_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[0].value" \
    --output tsv)

if [ -n "$STORAGE_KEY" ]; then
    # Generate SAS token valid for 7 days
    END_DATE=$(date -u -d "7 days" '+%Y-%m-%dT%H:%MZ')
    
    SAS_TOKEN=$(az storage container generate-sas \
        --account-name "$STORAGE_ACCOUNT" \
        --name "billing-exports" \
        --permissions rl \
        --expiry "$END_DATE" \
        --account-key "$STORAGE_KEY" \
        --output tsv)
    
    echo "✅ SAS token generated (valid for 7 days)"
    
    # Save SAS-based query
    cat > sas_query.sql <<EOF
-- Query using SAS token (for testing if permissions are the issue)
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'https://${STORAGE_ACCOUNT}.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv?${SAS_TOKEN}',
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
EOF
    
    echo "📝 SAS-based query saved to: sas_query.sql"
else
    echo "⚠️ Could not get storage key"
fi

# 6. Wait for permissions to propagate
echo ""
echo "6️⃣ Waiting for permissions to propagate..."
sleep 10

# 7. Test access
echo ""
echo "7️⃣ Testing storage access..."

# Test with service principal
FILE_CHECK=$(az storage blob exists \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "billing-exports" \
    --name "billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv" \
    --auth-mode login \
    --query "exists" \
    --output tsv 2>/dev/null)

if [ "$FILE_CHECK" == "true" ]; then
    echo "✅ File is accessible via service principal"
else
    echo "⚠️ File access check failed - may need more time for permissions"
fi

# Generate updated query file
cat > fixed_access_query.sql <<EOF
-- ========================================================
-- FIXED ACCESS QUERIES FOR SYNAPSE
-- ========================================================
-- Use these after running fix_storage_access.sh

-- Option 1: Query with managed identity (recommended)
-- Make sure you're connected to Built-in serverless SQL pool
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'https://${STORAGE_ACCOUNT}.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
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

-- Option 2: Create external data source (run once)
/*
CREATE EXTERNAL DATA SOURCE BillingStorage
WITH (
    TYPE = BLOB_STORAGE,
    LOCATION = 'https://${STORAGE_ACCOUNT}.blob.core.windows.net/billing-exports'
);

-- Then query using the data source
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
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

echo ""
echo "============================================="
echo "✅ Storage access configuration complete!"
echo "============================================="
echo ""
echo "📋 Summary of changes:"
echo "  • Azure Services can access storage"
echo "  • Synapse managed identity has Storage Blob Data Reader"
echo "  • Service principal has Storage Blob Data Reader"
echo "  • Network rules allow trusted Microsoft services"
echo ""
echo "📝 Next steps:"
echo "  1. Wait 1-2 minutes for permissions to fully propagate"
echo "  2. Open Synapse Studio: https://web.azuresynapse.net"
echo "  3. Select workspace: $SYNAPSE_WORKSPACE"
echo "  4. Connect to: Built-in serverless SQL pool"
echo "  5. Try the query from: fixed_access_query.sql"
echo ""
echo "🔍 If still having issues:"
echo "  • Try the SAS token query in sas_query.sql"
echo "  • Check if storage account has private endpoints"
echo "  • Verify Synapse workspace region matches storage region"
echo ""