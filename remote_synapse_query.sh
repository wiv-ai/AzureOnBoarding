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

# Function to execute SQL query via REST API
execute_synapse_query() {
    local QUERY=$1
    echo ""
    echo "📊 Executing query..."
    
    # Get access token
    ACCESS_TOKEN=$(az account get-access-token --resource "https://dev.azuresynapse.net" --query accessToken -o tsv)
    
    # Prepare query payload
    QUERY_PAYLOAD=$(cat <<EOF
{
    "query": "$QUERY",
    "limit": 100
}
EOF
)
    
    # Execute query via REST API
    RESPONSE=$(curl -s -X POST \
        "https://$SYNAPSE_WORKSPACE.dev.azuresynapse.net/sql/pools/Built-in/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$QUERY_PAYLOAD")
    
    echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
}

# Test 1: Check billing export status
echo ""
echo "📁 Checking billing export status..."
EXPORT_STATUS=$(az rest --method GET \
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/DailyBillingExport?api-version=2021-10-01" \
    --query "properties.schedule.status" -o tsv)
echo "Export Status: $EXPORT_STATUS"

# Test 2: List billing data files
echo ""
echo "📂 Checking for billing data files in storage..."
FILE_COUNT=$(az storage blob list \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER" \
    --prefix "billing-data/" \
    --auth-mode login \
    --query "length(@)" -o tsv 2>/dev/null || echo "0")

if [ "$FILE_COUNT" == "0" ] || [ -z "$FILE_COUNT" ]; then
    echo "⚠️  No billing data files found yet"
    echo ""
    read -p "Do you want to trigger the billing export now? (y/n): " TRIGGER
    
    if [[ "$TRIGGER" =~ ^[Yy]$ ]]; then
        echo "🔄 Triggering billing export..."
        az rest --method POST \
            --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/DailyBillingExport/run?api-version=2021-10-01" \
            --output none
        echo "✅ Export triggered. Data will be available in 5-15 minutes."
    fi
else
    echo "✅ Found $FILE_COUNT billing data file(s)"
fi

# Test 3: Query Synapse using REST API
echo ""
echo "🔷 Testing Synapse query via REST API..."

# Simple test query
TEST_QUERY="SELECT 'Connected to Synapse' as Status, GETDATE() as CurrentTime"

# Execute via REST API
execute_synapse_query "$TEST_QUERY"

# Test 4: Query billing data
echo ""
echo "📊 Querying billing data from Synapse..."

BILLING_QUERY="SELECT TOP 10 Date, ServiceFamily, ResourceGroup, CostInUSD FROM OPENROWSET(BULK 'https://$STORAGE_ACCOUNT.blob.core.windows.net/$CONTAINER/billing-data/*.csv', FORMAT = 'CSV', HEADER_ROW = TRUE) AS BillingData ORDER BY Date DESC"

execute_synapse_query "$BILLING_QUERY"

echo ""
echo "✅ Remote query test complete!"
echo ""
echo "📝 You can now query Synapse remotely using this script or the Azure CLI commands shown above."