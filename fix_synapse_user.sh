#!/bin/bash

# Configuration from your latest deployment
WORKSPACE="wiv-synapse-billing-24895"
APP_ID="52e9e7c8-5e81-4cc6-81c1-f8931a008f3f"

echo "========================================"
echo "🔧 FIXING SYNAPSE DATABASE USER"
echo "========================================"
echo "Workspace: $WORKSPACE"
echo "Service Principal: $APP_ID"
echo ""

# Get access token
echo "🔐 Getting Azure access token..."
TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv)

if [ -z "$TOKEN" ]; then
    echo "❌ Failed to get access token. Please run 'az login' first."
    exit 1
fi

echo "✅ Got access token"
echo ""

# Create database
echo "📝 Creating database if not exists..."
curl -X POST \
  "https://${WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/master/query" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query": "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = '\''BillingAnalytics'\'') CREATE DATABASE BillingAnalytics"}' \
  -s -o /tmp/db_create.json

echo "✅ Database creation attempted"
echo ""

# Wait a bit for database to be created
sleep 5

# Create user and grant permissions
echo "📝 Creating user and granting permissions..."
SQL_QUERY="IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##') CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd2024!'; IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account') CREATE USER [wiv_account] FROM EXTERNAL PROVIDER; ALTER ROLE db_datareader ADD MEMBER [wiv_account]; ALTER ROLE db_datawriter ADD MEMBER [wiv_account]; ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];"

curl -X POST \
  "https://${WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"$SQL_QUERY\"}" \
  -s -o /tmp/user_create.json

echo "✅ User creation and permissions attempted"
echo ""

# Check results
echo "📋 Results:"
echo "Database creation response:"
cat /tmp/db_create.json 2>/dev/null | jq '.' 2>/dev/null || cat /tmp/db_create.json 2>/dev/null || echo "No response"
echo ""
echo "User creation response:"
cat /tmp/user_create.json 2>/dev/null | jq '.' 2>/dev/null || cat /tmp/user_create.json 2>/dev/null || echo "No response"

echo ""
echo "========================================"
echo "✅ DONE!"
echo "========================================"
echo ""
echo "Now test with: python3 test_remote_query.py"