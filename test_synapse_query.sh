#!/bin/bash

echo "🔍 Testing Synapse Connection and Billing Queries"
echo "=================================================="

# Configuration from your output
TENANT_ID="ba153ff0-3397-4ef5-a214-dd33e8c37bff"
APP_ID="030cce2a-e94a-4d6f-9455-f8577c1721cb"
CLIENT_SECRET="Kxk8Q~LzvG1jl9halVfv4OH.ZgSshbZER108Hcuh"
SYNAPSE_WORKSPACE="wiv-synapse-billing"
STORAGE_ACCOUNT="billingstorage73919"
CONTAINER="billing-exports"
SUBSCRIPTION_ID="62b32106-4b98-47ea-9ac5-4181f33ae2af"

echo "📊 Configuration:"
echo "  - Synapse Workspace: $SYNAPSE_WORKSPACE"
echo "  - Storage Account: $STORAGE_ACCOUNT"
echo "  - Container: $CONTAINER"
echo ""

# Login using service principal
echo "🔐 Logging in with service principal..."
az login --service-principal \
    --username "$APP_ID" \
    --password "$CLIENT_SECRET" \
    --tenant "$TENANT_ID" \
    --only-show-errors

# Set subscription
az account set --subscription "$SUBSCRIPTION_ID"

# Test 1: Check if billing export exists
echo ""
echo "📁 Checking billing export status..."
az rest --method GET \
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/DailyBillingExport?api-version=2021-10-01" \
    --query "properties.schedule.status" -o tsv

# Test 2: List files in billing storage
echo ""
echo "📂 Checking for billing data files..."
az storage blob list \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER" \
    --prefix "billing-data/" \
    --query "[].name" \
    --output table \
    --only-show-errors 2>/dev/null || echo "No billing data files yet (export may not have run)"

# Test 3: Create a test query file
echo ""
echo "📝 Creating test query..."
cat > test_billing_query.sql <<EOF
-- Test query to check Synapse access to billing data
SELECT TOP 10 
    Date,
    ServiceFamily,
    ResourceGroup,
    CostInUSD,
    SubscriptionName
FROM OPENROWSET(
    BULK 'https://$STORAGE_ACCOUNT.blob.core.windows.net/$CONTAINER/billing-data/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
ORDER BY Date DESC
EOF

echo "✅ Test query created: test_billing_query.sql"

# Test 4: Try to trigger the billing export to run now
echo ""
read -p "Do you want to trigger the billing export to run now? (y/n): " TRIGGER

if [[ "$TRIGGER" =~ ^[Yy]$ ]]; then
    echo "🔄 Triggering billing export..."
    RESPONSE=$(az rest --method POST \
        --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/DailyBillingExport/run?api-version=2021-10-01" \
        2>&1)
    
    if [[ "$RESPONSE" == *"error"* ]]; then
        echo "⚠️  Export trigger failed. This might be because:"
        echo "   - Export is already running"
        echo "   - Export was recently triggered"
        echo "   - Need to wait for initial schedule"
    else
        echo "✅ Export triggered successfully!"
        echo "   Data will be available in 5-15 minutes"
    fi
fi

# Test 5: Generate ready-to-use Synapse Studio query
echo ""
echo "📊 Ready-to-use query for Synapse Studio:"
echo "========================================="
cat <<EOF

-- Copy and paste this into Synapse Studio
-- Connect to: Built-in (serverless SQL pool)

-- Check if billing data exists
SELECT TOP 10 
    Date,
    ServiceFamily,
    ResourceGroup,
    CAST(CostInUSD AS FLOAT) as CostUSD,
    SubscriptionName
FROM OPENROWSET(
    BULK 'https://$STORAGE_ACCOUNT.blob.core.windows.net/$CONTAINER/billing-data/*.csv',
    FORMAT = 'CSV',
    HEADER_ROW = TRUE
) AS BillingData
ORDER BY Date DESC;

-- If no data yet, the export needs to run first.
-- Exports run daily or can be triggered manually.

EOF

echo ""
echo "📌 Next Steps:"
echo "1. Open Synapse Studio: https://web.azuresynapse.net"
echo "2. Sign in with your Azure credentials"
echo "3. Go to 'Develop' > 'SQL scripts' > 'New SQL script'"
echo "4. Connect to 'Built-in' serverless SQL pool"
echo "5. Paste the query above and run it"
echo ""
echo "✅ Test complete!"