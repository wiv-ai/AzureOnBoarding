#!/bin/bash

# Fix script to create database user for existing Synapse workspace
echo "🔧 Fixing database user for Synapse workspace..."

WORKSPACE="wiv-synapse-billing-16098"
RESOURCE_GROUP="rg-wiv"
APP_ID="52e9e7c8-5e81-4cc6-81c1-f8931a008f3f"

# Get Azure user token
echo "Getting Azure access token..."
TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv)

if [ -z "$TOKEN" ]; then
    echo "❌ Could not get access token. Please run: az login"
    exit 1
fi

# Create SQL commands
SQL_COMMANDS="
-- Create database if not exists
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics')
    CREATE DATABASE BillingAnalytics;
GO

USE BillingAnalytics;
GO

-- Create master key
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd2024!';
GO

-- Create user for service principal
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account')
BEGIN
    CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
    PRINT 'Created user wiv_account';
END
GO

-- Grant permissions
ALTER ROLE db_datareader ADD MEMBER [wiv_account];
ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
GO
"

# Save to temp file
echo "$SQL_COMMANDS" > /tmp/fix_db_user.sql

# Try method 1: Using az synapse sql-script
echo "Method 1: Creating SQL script in Synapse..."
az synapse sql-script create \
    --workspace-name "$WORKSPACE" \
    --name "FixDatabaseUser_$(date +%s)" \
    --file /tmp/fix_db_user.sql \
    --resource-group "$RESOURCE_GROUP" \
    2>/dev/null && echo "✅ SQL script created in Synapse Studio" || echo "⚠️ Could not create SQL script"

# Try method 2: Direct REST API for database creation
echo "Method 2: Creating database via REST API..."
curl -X POST \
    "https://$WORKSPACE-ondemand.sql.azuresynapse.net/sql/databases/master/query" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"query": "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = '\''BillingAnalytics'\'') CREATE DATABASE BillingAnalytics"}' \
    --silent 2>&1 || true

sleep 5

# Try method 3: Grant permissions via REST API
echo "Method 3: Granting permissions via REST API..."
GRANT_SQL="USE BillingAnalytics; IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account') CREATE USER [wiv_account] FROM EXTERNAL PROVIDER; ALTER ROLE db_datareader ADD MEMBER [wiv_account]; ALTER ROLE db_datawriter ADD MEMBER [wiv_account]; ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];"

curl -X POST \
    "https://$WORKSPACE-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"$GRANT_SQL\"}" \
    --silent 2>&1 || true

# Clean up
rm -f /tmp/fix_db_user.sql

echo ""
echo "✅ Fix script completed!"
echo ""
echo "The script has attempted to create the database user using multiple methods."
echo "If it still doesn't work, you need to:"
echo "1. Open Synapse Studio: https://web.azuresynapse.net"
echo "2. Select workspace: $WORKSPACE"
echo "3. Go to Develop → New SQL script"
echo "4. Run the SQL from the script above"
echo ""
echo "Then test with: python3 test_remote_query.py"