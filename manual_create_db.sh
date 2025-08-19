#!/bin/bash

# Manual creation script for the new workspace
WORKSPACE="wiv-synapse-billing-37891"
STORAGE="billingstorage37858"
CONTAINER="billing-exports"
EXPORT_PATH="billing-data"

echo "🔧 Manually creating database and view for workspace: $WORKSPACE"
echo "=================================================="

# Get access token
echo "Getting access token..."
TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv)

if [ -z "$TOKEN" ]; then
    echo "❌ No token. Please run: az login"
    exit 1
fi

echo "✅ Got token"

# Step 1: Create database
echo ""
echo "Step 1: Creating database BillingAnalytics..."
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
    "https://$WORKSPACE-ondemand.sql.azuresynapse.net/sql/databases/master/query" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"query": "CREATE DATABASE BillingAnalytics"}')

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed -n '1,/HTTP_STATUS/p' | head -n -1)

if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "201" ] || [ "$HTTP_STATUS" = "202" ]; then
    echo "✅ Database created successfully!"
else
    echo "Status: $HTTP_STATUS"
    echo "Response: $BODY"
    if [[ "$BODY" == *"already exists"* ]]; then
        echo "✅ Database already exists"
    else
        echo "⚠️ Continuing anyway..."
    fi
fi

sleep 10

# Step 2: Create master key
echo ""
echo "Step 2: Creating master key..."
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
    "https://$WORKSPACE-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"query": "CREATE MASTER KEY ENCRYPTION BY PASSWORD = '\''StrongP@ssw0rd2024!'\''"}')

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "201" ] || [ "$HTTP_STATUS" = "202" ]; then
    echo "✅ Master key created!"
else
    echo "⚠️ Master key may already exist"
fi

sleep 5

# Step 3: Create user
echo ""
echo "Step 3: Creating user wiv_account..."
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
    "https://$WORKSPACE-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"query": "CREATE USER [wiv_account] FROM EXTERNAL PROVIDER"}')

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "201" ] || [ "$HTTP_STATUS" = "202" ]; then
    echo "✅ User created!"
else
    echo "⚠️ User may already exist"
fi

sleep 5

# Step 4: Grant permissions
echo ""
echo "Step 4: Granting permissions..."
curl -s -X POST \
    "https://$WORKSPACE-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"query": "ALTER ROLE db_datareader ADD MEMBER [wiv_account]; ALTER ROLE db_datawriter ADD MEMBER [wiv_account]; ALTER ROLE db_ddladmin ADD MEMBER [wiv_account]"}' \
    -o /dev/null

echo "✅ Permissions granted"

sleep 5

# Step 5: Create view
echo ""
echo "Step 5: Creating BillingData view..."
VIEW_SQL="CREATE VIEW BillingData AS SELECT * FROM OPENROWSET(BULK 'abfss://$CONTAINER@$STORAGE.dfs.core.windows.net/$EXPORT_PATH/*/*.csv', FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE) AS BillingExport"

RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
    "https://$WORKSPACE-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"$VIEW_SQL\"}")

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed -n '1,/HTTP_STATUS/p' | head -n -1)

if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "201" ] || [ "$HTTP_STATUS" = "202" ]; then
    echo "✅ View created successfully!"
else
    echo "Status: $HTTP_STATUS"
    echo "Response: $BODY"
    echo ""
    echo "Trying with https protocol instead..."
    
    VIEW_SQL_HTTPS="CREATE VIEW BillingDataHTTPS AS SELECT * FROM OPENROWSET(BULK 'https://$STORAGE.blob.core.windows.net/$CONTAINER/$EXPORT_PATH/*/*.csv', FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE) AS BillingExport"
    
    curl -s -X POST \
        "https://$WORKSPACE-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"$VIEW_SQL_HTTPS\"}" \
        -o /dev/null
    
    echo "✅ Alternative view created"
fi

echo ""
echo "============================================"
echo "✅ Setup complete!"
echo ""
echo "Test in Synapse Studio with:"
echo "  SELECT * FROM sys.databases WHERE name = 'BillingAnalytics';"
echo "  USE BillingAnalytics;"
echo "  SELECT * FROM sys.views;"
echo "  SELECT TOP 10 * FROM BillingData;"