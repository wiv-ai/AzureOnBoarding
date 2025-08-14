#!/bin/bash

echo "🔍 Remote Synapse Query via API"
echo "================================"

# Configuration
TENANT_ID="ba153ff0-3397-4ef5-a214-dd33e8c37bff"
APP_ID="030cce2a-e94a-4d6f-9455-f8577c1721cb"
CLIENT_SECRET="Kxk8Q~LzvG1jl9halVfv4OH.ZgSshbZER108Hcuh"
SYNAPSE_WORKSPACE="wiv-synapse-billing"
STORAGE_ACCOUNT="billingstorage73919"
CONTAINER="billing-exports"
SUBSCRIPTION_ID="62b32106-4b98-47ea-9ac5-4181f33ae2af"
RESOURCE_GROUP="wiv-rg"

# Login with service principal
echo "🔐 Logging in with service principal..."
az login --service-principal \
    --username "$APP_ID" \
    --password "$CLIENT_SECRET" \
    --tenant "$TENANT_ID" \
    --output none

# Set subscription
az account set --subscription "$SUBSCRIPTION_ID"
echo "✅ Logged in successfully"

# Test 1: Check billing export status
echo ""
echo "📁 Checking billing export status..."
EXPORT_STATUS=$(az rest --method GET \
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/DailyBillingExport?api-version=2021-10-01" \
    --query "properties.schedule.status" -o tsv)
echo "Export Status: $EXPORT_STATUS"

# Test 2: List billing data files (corrected path)
echo ""
echo "📂 Checking for billing data files in storage..."
echo "Looking for DailyBillingExport*.csv files..."

FILE_LIST=$(az storage blob list \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER" \
    --prefix "DailyBillingExport" \
    --auth-mode login \
    --query "[].name" \
    --output tsv 2>/dev/null)

if [ -z "$FILE_LIST" ]; then
    echo "⚠️  No billing data files found"
else
    echo "✅ Found billing data files:"
    echo "$FILE_LIST"
fi

# Test 3: Query billing data using correct path
echo ""
echo "📊 Testing Synapse query on billing data..."

# Create test query that reads the CSV files directly
cat > test_query.sql <<EOF
-- Query billing data from actual file location
SELECT TOP 10 
    *
FROM OPENROWSET(
    BULK 'https://$STORAGE_ACCOUNT.blob.core.windows.net/$CONTAINER/DailyBillingExport*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
ORDER BY Date DESC;
EOF

echo "Query saved to test_query.sql"
echo ""
echo "📝 To run this query:"
echo "1. Open Synapse Studio: https://web.azuresynapse.net"
echo "2. Select workspace: $SYNAPSE_WORKSPACE"
echo "3. Create new SQL script"
echo "4. Connect to: Built-in (serverless pool)"
echo "5. Run this query:"
echo ""
cat test_query.sql

# Test with az synapse sql query (if available)
echo ""
echo "🔷 Attempting to run query via CLI..."
az synapse sql query \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --query "SELECT TOP 5 * FROM OPENROWSET(BULK 'https://$STORAGE_ACCOUNT.blob.core.windows.net/$CONTAINER/DailyBillingExport*.csv', FORMAT = 'CSV', HEADER_ROW = TRUE) AS BillingData" \
    2>/dev/null || echo "Note: Direct SQL execution requires Synapse workspace configuration. Use Synapse Studio instead."

echo ""
echo "✅ Script complete!"