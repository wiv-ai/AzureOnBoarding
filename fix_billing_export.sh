#!/bin/bash

# Fix Billing Export Creation Script
# This creates or updates the billing export with proper date handling

echo "🔧 Fixing Billing Export Configuration..."
echo "========================================"

# Configuration - update these if needed
APP_SUBSCRIPTION_ID="${1:-$(az account show --query id -o tsv)}"
EXPORT_NAME="DailyBillingExport"
STORAGE_ACCOUNT_NAME="${2:-billingstorage21024}"  # Update with your storage account
CONTAINER_NAME="billing-exports"
BILLING_RG="wiv-rg"

echo "Using subscription: $APP_SUBSCRIPTION_ID"
echo "Storage account: $STORAGE_ACCOUNT_NAME"

# Get storage account resource ID
STORAGE_RESOURCE_ID=$(az storage account show \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$BILLING_RG" \
    --query id -o tsv 2>/dev/null)

if [ -z "$STORAGE_RESOURCE_ID" ]; then
    echo "❌ Error: Storage account $STORAGE_ACCOUNT_NAME not found in resource group $BILLING_RG"
    echo "Please check the storage account name and try again."
    exit 1
fi

# Delete existing export if it exists (to start fresh)
echo "🗑️  Removing existing export if present..."
az rest --method DELETE \
    --uri "https://management.azure.com/subscriptions/$APP_SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME?api-version=2021-10-01" \
    2>/dev/null

sleep 2

# Create proper date values (handle both macOS and Linux)
echo "📅 Setting up date range..."
# Use a simpler approach - just use current date and a fixed future date
CURRENT_YEAR=$(date +%Y)
CURRENT_MONTH=$(date +%m)
CURRENT_DAY=$(date +%d)
FUTURE_YEAR=$((CURRENT_YEAR + 5))

START_DATE="${CURRENT_YEAR}-${CURRENT_MONTH}-${CURRENT_DAY}T00:00:00Z"
END_DATE="${FUTURE_YEAR}-${CURRENT_MONTH}-${CURRENT_DAY}T00:00:00Z"

echo "   Start: $START_DATE"
echo "   End: $END_DATE"

# Create the export with simplified JSON
echo "📊 Creating billing export..."
cat > export_config.json <<EOF
{
  "properties": {
    "schedule": {
      "status": "Active",
      "recurrence": "Daily",
      "recurrencePeriod": {
        "from": "$START_DATE",
        "to": "$END_DATE"
      }
    },
    "format": "Csv",
    "deliveryInfo": {
      "destination": {
        "resourceId": "$STORAGE_RESOURCE_ID",
        "container": "$CONTAINER_NAME",
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

# Create the export using the JSON file
EXPORT_RESPONSE=$(az rest --method PUT \
    --uri "https://management.azure.com/subscriptions/$APP_SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME?api-version=2021-10-01" \
    --body @export_config.json 2>&1)

# Check result
if [[ "$EXPORT_RESPONSE" == *"error"* ]]; then
    echo "❌ Error creating export:"
    echo "$EXPORT_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$EXPORT_RESPONSE"
    
    echo ""
    echo "📝 Troubleshooting:"
    echo "1. Check if you have Cost Management Reader role"
    echo "2. Verify the storage account exists: $STORAGE_ACCOUNT_NAME"
    echo "3. Try running: az login --tenant <your-tenant-id>"
else
    echo "✅ Billing export created successfully!"
    
    # Verify the export
    echo ""
    echo "🔍 Verifying export configuration..."
    az rest --method GET \
        --uri "https://management.azure.com/subscriptions/$APP_SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME?api-version=2021-10-01" \
        --query "{name:name, status:properties.schedule.status, recurrence:properties.schedule.recurrence}" \
        -o table
    
    # Trigger immediate run
    echo ""
    echo "🚀 Triggering immediate export run..."
    az rest --method POST \
        --uri "https://management.azure.com/subscriptions/$APP_SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME/run?api-version=2021-10-01" \
        2>/dev/null && echo "✅ Export triggered! Data will be available in 5-30 minutes." || echo "⚠️  Export will run at midnight UTC"
fi

# Cleanup
rm -f export_config.json

echo ""
echo "✅ Done! Check your storage account in 5-30 minutes:"
echo "   Storage: $STORAGE_ACCOUNT_NAME"
echo "   Container: $CONTAINER_NAME/billing-data/"