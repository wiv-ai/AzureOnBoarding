#!/bin/bash

# This script fixes the database user creation issue
# Run this on your Mac where Azure CLI is available

WORKSPACE="wiv-synapse-billing-27063"
APP_ID="52e9e7c8-5e81-4cc6-81c1-f8931a008f3f"

echo "========================================"
echo "🔧 FIXING DATABASE USER FOR SYNAPSE"
echo "========================================"
echo "Workspace: $WORKSPACE"
echo "Service Principal: $APP_ID"
echo ""

# Check if logged in
CURRENT_USER=$(az account show --query user.name -o tsv 2>/dev/null)
if [ -z "$CURRENT_USER" ]; then
    echo "❌ Not logged in to Azure CLI"
    echo "Please run: az login"
    exit 1
fi

echo "✅ Logged in as: $CURRENT_USER"
echo ""

# Get access token
echo "🔐 Getting Azure access token..."
TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv)

if [ -z "$TOKEN" ]; then
    echo "❌ Failed to get access token"
    exit 1
fi

echo "✅ Got access token"
echo ""

# The REST API doesn't work properly for serverless pools
# We need to use sqlcmd instead

echo "📝 Installing sqlcmd if needed..."
if ! command -v sqlcmd &> /dev/null; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install sqlcmd
    else
        echo "Please install sqlcmd manually"
        exit 1
    fi
fi

echo ""
echo "📝 Creating SQL script..."
cat > /tmp/fix_synapse_user.sql <<EOF
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
    CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
GO

-- Grant permissions
ALTER ROLE db_datareader ADD MEMBER [wiv_account];
ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
GO

SELECT 'Database user created successfully!' as Result;
GO
EOF

echo "✅ SQL script created"
echo ""

echo "📝 Executing SQL using sqlcmd with Azure AD authentication..."
sqlcmd -S ${WORKSPACE}-ondemand.sql.azuresynapse.net \
       -d master \
       -G \
       -i /tmp/fix_synapse_user.sql

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Database user created successfully!"
    echo ""
    echo "You can now test with: python3 test_remote_query.py"
else
    echo ""
    echo "⚠️ sqlcmd failed. Trying alternative method..."
    echo ""
    echo "Please run this SQL manually in Synapse Studio:"
    echo "1. Open: https://web.azuresynapse.net"
    echo "2. Select workspace: $WORKSPACE"
    echo "3. Run the SQL from: /tmp/fix_synapse_user.sql"
fi

# Clean up
rm -f /tmp/fix_synapse_user.sql