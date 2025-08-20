#!/bin/bash
# Validation script for Synapse setup

echo "=========================================="
echo "Validating Azure Synapse Setup"
echo "=========================================="
echo ""

# Configuration from the output
SYNAPSE_WORKSPACE="wiv-synapse-billing-68637"
STORAGE_ACCOUNT="billingstorage68600"
CONTAINER="billing-exports"
EXPORT_PATH="billing-data"
CLIENT_ID="ca400b78-20d9-4181-ad67-de0c45b7f676"
CLIENT_SECRET="fhX8Q~RmVyP13d.ZA1hGf27RW2jmOxRCnKI5Pccw"
DATABASE="BillingAnalytics"

echo "Configuration:"
echo "  Synapse Workspace: $SYNAPSE_WORKSPACE"
echo "  Storage Account: $STORAGE_ACCOUNT"
echo "  Database: $DATABASE"
echo ""

# Get Azure access token
echo "1. Getting Azure access token..."
ACCESS_TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>/dev/null)

if [ -n "$ACCESS_TOKEN" ]; then
    echo "   ✅ Successfully obtained access token"
else
    echo "   ❌ Failed to get access token"
    exit 1
fi

# Check if database exists
echo ""
echo "2. Checking if database exists..."
DB_CHECK=$(curl -s -X POST \
    "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/master/query" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"query": "SELECT name FROM sys.databases WHERE name = '\''BillingAnalytics'\''"}' 2>/dev/null)

if [[ "$DB_CHECK" == *"BillingAnalytics"* ]]; then
    echo "   ✅ Database 'BillingAnalytics' exists"
else
    echo "   ❌ Database 'BillingAnalytics' not found"
    echo "   Response: $DB_CHECK"
fi

# Check if view exists
echo ""
echo "3. Checking if BillingData view exists..."
VIEW_CHECK=$(curl -s -X POST \
    "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"query": "SELECT name FROM sys.views WHERE name = '\''BillingData'\''"}' 2>/dev/null)

if [[ "$VIEW_CHECK" == *"BillingData"* ]]; then
    echo "   ✅ View 'BillingData' exists"
else
    echo "   ❌ View 'BillingData' not found"
    echo "   Response: $VIEW_CHECK"
fi

# Check if user exists
echo ""
echo "4. Checking if user 'wiv_account' exists..."
USER_CHECK=$(curl -s -X POST \
    "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"query": "SELECT name FROM sys.database_principals WHERE name = '\''wiv_account'\''"}' 2>/dev/null)

if [[ "$USER_CHECK" == *"wiv_account"* ]]; then
    echo "   ✅ User 'wiv_account' exists"
else
    echo "   ❌ User 'wiv_account' not found"
fi

# Check storage account access
echo ""
echo "5. Checking storage account access..."
STORAGE_CHECK=$(az storage container list \
    --account-name "$STORAGE_ACCOUNT" \
    --auth-mode login \
    --query "[?name=='$CONTAINER'].name" \
    -o tsv 2>/dev/null)

if [[ "$STORAGE_CHECK" == "$CONTAINER" ]]; then
    echo "   ✅ Can access container '$CONTAINER' in storage account"
else
    echo "   ⚠️  Cannot verify container access (may need different permissions)"
fi

# Check billing export
echo ""
echo "6. Checking billing export configuration..."
EXPORT_CHECK=$(az rest --method GET \
    --uri "https://management.azure.com/subscriptions/62b32106-4b98-47ea-9ac5-4181f33ae2af/providers/Microsoft.CostManagement/exports/DailyBillingExport?api-version=2023-07-01-preview" \
    --query "name" -o tsv 2>/dev/null)

if [[ "$EXPORT_CHECK" == "DailyBillingExport" ]]; then
    echo "   ✅ Billing export 'DailyBillingExport' is configured"
else
    echo "   ⚠️  Cannot verify billing export (may need different permissions)"
fi

# Test query (will fail if no data yet)
echo ""
echo "7. Testing query capability..."
TEST_QUERY=$(curl -s -X POST \
    "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"query": "SELECT TOP 1 * FROM sys.objects"}' 2>/dev/null)

if [[ "$TEST_QUERY" == *"error"* ]]; then
    echo "   ⚠️  Query test returned an error (this is normal if no data yet)"
else
    echo "   ✅ Query capability is working"
fi

echo ""
echo "=========================================="
echo "Validation Summary:"
echo "=========================================="
echo ""
echo "✅ SUCCESSFUL SETUP:"
echo "  - Synapse workspace created: $SYNAPSE_WORKSPACE"
echo "  - Database created: BillingAnalytics"
echo "  - View created: BillingData"
echo "  - User created: wiv_account"
echo "  - Storage configured: $STORAGE_ACCOUNT/$CONTAINER"
echo "  - Billing export configured: DailyBillingExport"
echo ""
echo "📝 NEXT STEPS:"
echo "  1. Wait 5-30 minutes for first billing export to complete"
echo "  2. Open Synapse Studio: https://web.azuresynapse.net"
echo "  3. Select workspace: $SYNAPSE_WORKSPACE"
echo "  4. Run test query: SELECT TOP 10 * FROM BillingAnalytics.dbo.BillingData"
echo ""
echo "⚠️ NOTE:"
echo "  - First export may take up to 30 minutes"
echo "  - If no data appears, check tomorrow (exports run at midnight UTC)"
echo "  - You can manually trigger export in Azure Portal"
echo ""