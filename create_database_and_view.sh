#!/bin/bash

# Configuration from the script output
WORKSPACE_NAME="wiv-synapse-billing-33923"
DATABASE_NAME="BillingAnalytics"
STORAGE_ACCOUNT="billingstorage33888"
CONTAINER="billing-exports"
EXPORT_PATH="billing-data"

echo "🔧 Creating database and user in Synapse..."

# Get access token for current Azure user
ACCESS_TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv)

if [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ Failed to get Azure access token"
    exit 1
fi

echo "✅ Got Azure access token"

# Create database if not exists
echo "📝 Creating database..."
curl -X POST \
    "https://$WORKSPACE_NAME-ondemand.sql.azuresynapse.net/sql/databases/master/query" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"query": "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = '\''BillingAnalytics'\'') CREATE DATABASE BillingAnalytics"}' \
    -o /tmp/db_create.json 2>/dev/null

echo "✅ Database creation attempted"
sleep 5

# Create user and grant permissions
echo "📝 Creating user wiv_account and granting permissions..."

SQL_COMMAND="IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##') CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd!2024';
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account') CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [wiv_account];
ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];"

curl -X POST \
    "https://$WORKSPACE_NAME-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"$SQL_COMMAND\"}" \
    -o /tmp/user_create.json 2>/dev/null

echo "✅ User creation attempted"
sleep 5

# Create the BillingData view
echo "📝 Creating BillingData view..."

VIEW_SQL="CREATE OR ALTER VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK 'https://$STORAGE_ACCOUNT.blob.core.windows.net/$CONTAINER/$EXPORT_PATH/*/*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport"

curl -X POST \
    "https://$WORKSPACE_NAME-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"$VIEW_SQL\"}" \
    -o /tmp/view_create.json 2>/dev/null

echo "✅ View creation attempted"

# Show results
echo ""
echo "📊 Results:"
echo "Database creation response:"
cat /tmp/db_create.json 2>/dev/null | jq '.' 2>/dev/null || cat /tmp/db_create.json 2>/dev/null
echo ""
echo "User creation response:"
cat /tmp/user_create.json 2>/dev/null | jq '.' 2>/dev/null || cat /tmp/user_create.json 2>/dev/null
echo ""
echo "View creation response:"
cat /tmp/view_create.json 2>/dev/null | jq '.' 2>/dev/null || cat /tmp/view_create.json 2>/dev/null

echo ""
echo "✅ Setup complete! Now test with: python3 check_view.py"