#!/bin/bash

echo "🔷 Testing Remote Synapse Query Execution"
echo "=========================================="

# Configuration
SYNAPSE_WORKSPACE="wiv-synapse-billing"
STORAGE_ACCOUNT="billingstorage77626"
FILE_PATH="billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv"

# Create a simple test query
SIMPLE_QUERY="SELECT TOP 5 * FROM OPENROWSET(BULK 'https://${STORAGE_ACCOUNT}.blob.core.windows.net/billing-exports/${FILE_PATH}', FORMAT = 'CSV', PARSER_VERSION = '2.0', FIRSTROW = 2) WITH (Date NVARCHAR(100), ServiceFamily NVARCHAR(100), ResourceGroup NVARCHAR(100), CostInUSD NVARCHAR(50)) AS BillingData"

echo "📊 Executing query on Synapse..."
echo "Query: SELECT TOP 5 rows from billing data"
echo ""

# Try using az synapse sql query command
az synapse sql query \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --query-text "$SIMPLE_QUERY" \
    --database-name "master" \
    2>&1

RESULT=$?

if [ $RESULT -eq 0 ]; then
    echo ""
    echo "✅ Query executed successfully!"
else
    echo ""
    echo "⚠️ Query execution failed. This might be due to:"
    echo "   1. Service principal needs Synapse SQL Administrator role"
    echo "   2. Firewall rules need to be configured"
    echo "   3. The query needs to be run from Synapse Studio instead"
fi

echo ""
echo "📝 Alternative: Use Synapse Studio"
echo "   1. Go to: https://web.azuresynapse.net"
echo "   2. Select workspace: $SYNAPSE_WORKSPACE"
echo "   3. Use the query from validated_query.sql"
