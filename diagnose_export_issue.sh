#!/bin/bash

echo "🔍 Diagnosing Billing Export Issue"
echo "==================================="

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "Subscription ID: $SUBSCRIPTION_ID"

# Check if export already exists
echo ""
echo "1️⃣ Checking if export already exists..."
EXPORT_CHECK=$(az rest --method GET \
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/DailyBillingExport?api-version=2021-10-01" 2>&1)

if [[ "$EXPORT_CHECK" == *"NotFound"* ]]; then
    echo "❌ Export does not exist"
elif [[ "$EXPORT_CHECK" == *"properties"* ]]; then
    echo "✅ Export already exists!"
    echo "$EXPORT_CHECK" | python3 -m json.tool | head -20
else
    echo "⚠️ Unexpected response:"
    echo "$EXPORT_CHECK" | head -20
fi

# Check storage account
echo ""
echo "2️⃣ Checking storage account..."
STORAGE_ACCOUNTS=$(az storage account list --resource-group wiv-rg --query "[].name" -o tsv)
echo "Storage accounts in wiv-rg: $STORAGE_ACCOUNTS"

# Get the actual storage account name
STORAGE_ACCOUNT=$(echo "$STORAGE_ACCOUNTS" | grep billing | head -1)
if [ -z "$STORAGE_ACCOUNT" ]; then
    STORAGE_ACCOUNT=$(echo "$STORAGE_ACCOUNTS" | head -1)
fi
echo "Using storage account: $STORAGE_ACCOUNT"

# Check permissions
echo ""
echo "3️⃣ Checking your permissions..."
ROLES=$(az role assignment list --assignee $(az account show --query user.name -o tsv) --query "[].roleDefinitionName" -o tsv | grep -i cost)
if [ -n "$ROLES" ]; then
    echo "Cost-related roles: $ROLES"
else
    echo "⚠️ No Cost Management roles found. You need 'Cost Management Contributor' role"
fi

# Try creating with minimal config
echo ""
echo "4️⃣ Attempting minimal export creation..."

STORAGE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/wiv-rg/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"

cat > minimal_export.json <<EOF
{
  "properties": {
    "schedule": {
      "status": "Active",
      "recurrence": "Daily",
      "recurrencePeriod": {
        "from": "2025-01-01T00:00:00Z",
        "to": "2030-01-01T00:00:00Z"
      }
    },
    "deliveryInfo": {
      "destination": {
        "resourceId": "$STORAGE_ID",
        "container": "billing-exports"
      }
    },
    "definition": {
      "type": "ActualCost",
      "timeframe": "MonthToDate",
      "dataSet": {
        "granularity": "Daily"
      }
    }
  }
}
EOF

echo "Attempting to create export..."
CREATE_RESULT=$(az rest --method PUT \
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/TestExport?api-version=2021-10-01" \
    --body @minimal_export.json 2>&1)

if [[ "$CREATE_RESULT" == *"error"* ]]; then
    echo "❌ Creation failed with error:"
    echo "$CREATE_RESULT" | python3 -m json.tool 2>/dev/null || echo "$CREATE_RESULT"
    
    echo ""
    echo "📝 Common issues:"
    echo "1. Missing 'Cost Management Contributor' role"
    echo "2. Subscription doesn't support Cost Management exports"
    echo "3. Storage account doesn't exist or wrong name"
    echo "4. Container 'billing-exports' doesn't exist"
else
    echo "✅ Test export created successfully!"
    # Clean up test export
    az rest --method DELETE \
        --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/TestExport?api-version=2021-10-01" 2>/dev/null
fi

rm -f minimal_export.json

echo ""
echo "5️⃣ Manual fix instructions:"
echo "----------------------------"
echo "Option 1: Grant yourself the role:"
echo "  az role assignment create \\"
echo "    --assignee $(az account show --query user.name -o tsv) \\"
echo "    --role 'Cost Management Contributor' \\"
echo "    --scope /subscriptions/$SUBSCRIPTION_ID"
echo ""
echo "Option 2: Create manually in Azure Portal:"
echo "  1. Go to: https://portal.azure.com"
echo "  2. Navigate to: Cost Management + Billing"
echo "  3. Select: Exports"
echo "  4. Click: + Add"
echo "  5. Configure:"
echo "     - Name: DailyBillingExport"
echo "     - Type: Daily export of month-to-date costs"
echo "     - Storage: $STORAGE_ACCOUNT"
echo "     - Container: billing-exports"
echo "     - Path: billing-data"