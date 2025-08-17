#!/bin/bash
# Quick fix for billing export - run this after main script

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
STORAGE_ACCOUNT="billingstorage21024"  # Update if different
STORAGE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/wiv-rg/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"

# Delete broken export
az rest --method DELETE \
  --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/DailyBillingExport?api-version=2021-10-01" 2>/dev/null

# Create with simple dates
START=$(date +%Y-%m-%d)
END="2029-$(date +%m-%d)"

cat > export.json <<EOF
{
  "properties": {
    "schedule": {
      "status": "Active",
      "recurrence": "Daily",
      "recurrencePeriod": {
        "from": "${START}T00:00:00Z",
        "to": "${END}T00:00:00Z"
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
        "granularity": "Daily"
      }
    }
  }
}
EOF

az rest --method PUT \
  --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/DailyBillingExport?api-version=2021-10-01" \
  --body @export.json

rm export.json
echo "✅ Export fixed!"