#!/bin/bash

# Configuration from latest run
WORKSPACE_NAME="wiv-synapse-billing-35674"
DATABASE_NAME="BillingAnalytics"
STORAGE_ACCOUNT="billingstorage35639"
CONTAINER="billing-exports"
EXPORT_PATH="billing-data"

echo "🔧 Fixing Synapse database and view..."
echo "Workspace: $WORKSPACE_NAME"

# Get fresh access token
echo "Getting Azure access token..."
ACCESS_TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ No access token. Please run: az login"
    exit 1
fi

echo "✅ Got access token"

# Step 1: Create database
echo ""
echo "Step 1: Creating database BillingAnalytics..."
curl -X POST \
    "https://$WORKSPACE_NAME-ondemand.sql.azuresynapse.net/sql/databases/master/query" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"query": "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = '\''BillingAnalytics'\'') CREATE DATABASE BillingAnalytics"}' \
    -w "\nHTTP Status: %{http_code}\n" 2>/dev/null

echo "Waiting for database to be ready..."
sleep 10

# Step 2: Create master key
echo ""
echo "Step 2: Creating master key..."
curl -X POST \
    "https://$WORKSPACE_NAME-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"query": "IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '\''##MS_DatabaseMasterKey##'\'') CREATE MASTER KEY ENCRYPTION BY PASSWORD = '\''StrongP@ssw0rd2024!'\''"}' \
    -w "\nHTTP Status: %{http_code}\n" 2>/dev/null

sleep 5

# Step 3: Create user
echo ""
echo "Step 3: Creating user wiv_account..."
curl -X POST \
    "https://$WORKSPACE_NAME-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"query": "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '\''wiv_account'\'') CREATE USER [wiv_account] FROM EXTERNAL PROVIDER"}' \
    -w "\nHTTP Status: %{http_code}\n" 2>/dev/null

sleep 5

# Step 4: Grant permissions
echo ""
echo "Step 4: Granting permissions..."
curl -X POST \
    "https://$WORKSPACE_NAME-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"query": "ALTER ROLE db_datareader ADD MEMBER [wiv_account]; ALTER ROLE db_datawriter ADD MEMBER [wiv_account]; ALTER ROLE db_ddladmin ADD MEMBER [wiv_account]"}' \
    -w "\nHTTP Status: %{http_code}\n" 2>/dev/null

sleep 5

# Step 5: Create view with abfss protocol (Managed Identity)
echo ""
echo "Step 5: Creating BillingData view (abfss protocol)..."
curl -X POST \
    "https://$WORKSPACE_NAME-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"CREATE OR ALTER VIEW BillingData AS SELECT * FROM OPENROWSET(BULK 'abfss://$CONTAINER@$STORAGE_ACCOUNT.dfs.core.windows.net/$EXPORT_PATH/*/*.csv', FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE) AS BillingExport\"}" \
    -w "\nHTTP Status: %{http_code}\n" 2>/dev/null

# Step 6: Try alternate view with https protocol if needed
echo ""
echo "Step 6: Creating alternate view (https protocol as fallback)..."
curl -X POST \
    "https://$WORKSPACE_NAME-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"CREATE OR ALTER VIEW BillingDataHTTPS AS SELECT * FROM OPENROWSET(BULK 'https://$STORAGE_ACCOUNT.blob.core.windows.net/$CONTAINER/$EXPORT_PATH/*/*.csv', FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE) AS BillingExport\"}" \
    -w "\nHTTP Status: %{http_code}\n" 2>/dev/null

echo ""
echo "✅ Setup complete!"
echo ""
echo "📝 To verify, run: python3 check_view.py"
echo "   Or open Synapse Studio and check for:"
echo "   - Database: BillingAnalytics"
echo "   - View: BillingData"