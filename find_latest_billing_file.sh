#!/bin/bash

echo "🔍 Finding Latest Billing Export File"
echo "======================================"

# Configuration
STORAGE_ACCOUNT="billingstorage77626"
CONTAINER="billing-exports"
PREFIX="billing-data/DailyBillingExport"

# Check if logged in
if ! az account show &>/dev/null; then
    echo "❌ Not logged in to Azure. Please run the main startup script first."
    exit 1
fi

echo "📂 Searching for billing export files..."

# List all CSV files in the billing export directory
# Using tsv output to avoid needing jq
LATEST_FILE=$(az storage blob list \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER" \
    --prefix "$PREFIX" \
    --query "[?ends_with(name, '.csv')] | sort_by(@, &properties.lastModified) | [-1].name" \
    --output tsv 2>/dev/null)

if [ -z "$LATEST_FILE" ]; then
    echo "❌ Could not determine latest file"
    exit 1
fi

echo "✅ Found latest billing file:"
echo "   $LATEST_FILE"

# Extract date range from the path
DATE_RANGE=$(echo "$LATEST_FILE" | grep -oP '\d{8}-\d{8}' | head -1)
FILE_NAME=$(basename "$LATEST_FILE")

echo ""
echo "📊 File Details:"
echo "   Date Range: $DATE_RANGE"
echo "   File Name: $FILE_NAME"

# Generate the full URL
FULL_URL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER}/${LATEST_FILE}"

echo ""
echo "🔗 Full URL for Synapse queries:"
echo "   $FULL_URL"

# Generate SQL query file with the latest file
cat > latest_billing_query.sql <<EOF
-- ========================================================
-- SYNAPSE QUERY FOR LATEST BILLING FILE
-- ========================================================
-- Generated on: $(date)
-- Latest file: $FILE_NAME
-- Date range: $DATE_RANGE
-- ========================================================

-- Query the latest billing data
SELECT TOP 100 *
FROM OPENROWSET(
    BULK '$FULL_URL',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
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
) AS BillingData
ORDER BY Date DESC;

-- Daily cost summary
SELECT 
    CAST(Date AS DATE) as BillingDate,
    COUNT(*) as TransactionCount,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as DailyCostUSD
FROM OPENROWSET(
    BULK '$FULL_URL',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    Date NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE Date IS NOT NULL
GROUP BY CAST(Date AS DATE)
ORDER BY BillingDate DESC;

-- Service cost breakdown
SELECT 
    ServiceFamily,
    COUNT(*) as TransactionCount,
    SUM(TRY_CAST(CostInUSD as DECIMAL(18,2))) as TotalCostUSD
FROM OPENROWSET(
    BULK '$FULL_URL',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    ServiceFamily NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
WHERE ServiceFamily IS NOT NULL
GROUP BY ServiceFamily
ORDER BY TotalCostUSD DESC;
EOF

echo ""
echo "✅ Query file generated: latest_billing_query.sql"
echo ""
echo "📝 Next Steps:"
echo "1. Open Synapse Studio: https://web.azuresynapse.net"
echo "2. Select workspace: wiv-synapse-billing"
echo "3. Connect to: Built-in (serverless SQL pool)"
echo "4. Copy and run the queries from latest_billing_query.sql"
echo ""
echo "💡 Tip: Run this script periodically to get queries for the latest export file"