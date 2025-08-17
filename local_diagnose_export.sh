#!/bin/bash

echo "🔍 Diagnosing Billing Export Issue (Local Version)"
echo "=================================================="

# Ensure we're logged in
if ! az account show >/dev/null 2>&1; then
    echo "❌ Not logged in to Azure. Please run: az login"
    exit 1
fi

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "✅ Subscription ID: $SUBSCRIPTION_ID"

# Check if export already exists
echo ""
echo "1️⃣ Checking if DailyBillingExport exists..."
EXPORT_CHECK=$(az rest --method GET \
    --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/DailyBillingExport?api-version=2021-10-01" 2>&1)

if [[ "$EXPORT_CHECK" == *"NotFound"* ]] || [[ "$EXPORT_CHECK" == *"404"* ]]; then
    echo "❌ Export does not exist - will create it"
    EXPORT_EXISTS=false
elif [[ "$EXPORT_CHECK" == *"properties"* ]]; then
    echo "✅ Export already exists!"
    echo "   To view it: Azure Portal > Cost Management > Exports"
    EXPORT_EXISTS=true
else
    echo "⚠️ Cannot determine export status"
    EXPORT_EXISTS=false
fi

# If export doesn't exist, try to create it
if [ "$EXPORT_EXISTS" = "false" ]; then
    echo ""
    echo "2️⃣ Finding your storage account..."
    STORAGE_ACCOUNTS=$(az storage account list --resource-group wiv-rg --query "[].name" -o tsv 2>/dev/null)
    
    if [ -z "$STORAGE_ACCOUNTS" ]; then
        echo "❌ No storage accounts found in wiv-rg"
        echo "   Please check if the resource group exists"
        exit 1
    fi
    
    # Find the billing storage account
    STORAGE_ACCOUNT=$(echo "$STORAGE_ACCOUNTS" | grep -E "billing|storage" | head -1)
    if [ -z "$STORAGE_ACCOUNT" ]; then
        STORAGE_ACCOUNT=$(echo "$STORAGE_ACCOUNTS" | head -1)
    fi
    echo "✅ Using storage account: $STORAGE_ACCOUNT"
    
    # Get storage account resource ID
    STORAGE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/wiv-rg/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"
    
    echo ""
    echo "3️⃣ Creating billing export..."
    
    # Create the export with fixed dates
    cat > billing_export_fix.json <<EOF
{
  "properties": {
    "schedule": {
      "status": "Active",
      "recurrence": "Daily",
      "recurrencePeriod": {
        "from": "2024-01-01T00:00:00Z",
        "to": "2029-12-31T00:00:00Z"
      }
    },
    "format": "Csv",
    "deliveryInfo": {
      "destination": {
        "resourceId": "$STORAGE_ID",
        "container": "billing-exports",
        "rootFolderPath": "billing-data"
      }
    },
    "definition": {
      "type": "ActualCost",
      "timeframe": "MonthToDate",
      "dataSet": {
        "granularity": "Daily",
        "configuration": {
          "columns": [
            "Date",
            "ServiceFamily",
            "MeterCategory",
            "MeterSubcategory",
            "MeterName",
            "ResourceGroup",
            "ResourceLocation",
            "ConsumedService",
            "ResourceId",
            "ChargeType",
            "PublisherType",
            "Quantity",
            "CostInBillingCurrency",
            "CostInUsd",
            "BillingCurrencyCode",
            "SubscriptionName",
            "SubscriptionId",
            "ProductName",
            "Frequency",
            "UnitOfMeasure",
            "Tags"
          ]
        }
      }
    }
  }
}
EOF
    
    # Delete any existing broken export first
    echo "   Cleaning up any broken export..."
    az rest --method DELETE \
        --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/DailyBillingExport?api-version=2021-10-01" \
        >/dev/null 2>&1
    
    sleep 2
    
    # Create the export
    echo "   Creating new export..."
    CREATE_RESULT=$(az rest --method PUT \
        --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/DailyBillingExport?api-version=2021-10-01" \
        --body @billing_export_fix.json 2>&1)
    
    rm -f billing_export_fix.json
    
    if [[ "$CREATE_RESULT" == *"error"* ]]; then
        echo "❌ Export creation failed"
        echo ""
        echo "Error details:"
        echo "$CREATE_RESULT" | python3 -m json.tool 2>/dev/null || echo "$CREATE_RESULT" | head -5
        
        echo ""
        echo "🔧 Trying to fix permissions..."
        echo ""
        echo "Run this command to grant yourself permissions:"
        echo ""
        echo "az role assignment create \\"
        echo "  --assignee \"$(az account show --query user.name -o tsv)\" \\"
        echo "  --role \"Cost Management Contributor\" \\"
        echo "  --scope \"/subscriptions/$SUBSCRIPTION_ID\""
        echo ""
        echo "Then re-run this script."
    else
        echo "✅ Billing export created successfully!"
        
        # Trigger immediate run
        echo ""
        echo "4️⃣ Triggering immediate export run..."
        az rest --method POST \
            --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/DailyBillingExport/run?api-version=2021-10-01" \
            >/dev/null 2>&1 && echo "✅ Export triggered! Data will appear in 5-30 minutes." || echo "⚠️ Export will run at midnight UTC"
    fi
fi

echo ""
echo "=================================================="
echo "Summary:"
echo "  Subscription: $SUBSCRIPTION_ID"
if [ "$EXPORT_EXISTS" = "true" ]; then
    echo "  Export Status: ✅ Already exists"
else
    echo "  Storage Account: $STORAGE_ACCOUNT"
fi
echo "  Container: billing-exports/billing-data/"
echo ""
echo "Next steps:"
echo "  1. Wait 5-30 minutes for first export to complete"
echo "  2. Then query in Synapse: SELECT * FROM BillingAnalytics.dbo.BillingData"
echo "=================================================="