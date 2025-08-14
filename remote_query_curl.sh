#!/bin/bash

echo "======================================"
echo "Remote Synapse Query via REST API"
echo "======================================"

# Configuration
TENANT_ID="ba153ff0-3397-4ef5-a214-dd33e8c37bff"
CLIENT_ID="554b11c1-18f9-46b5-a096-30e0a2cfae6f"
CLIENT_SECRET="tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams"
SYNAPSE_WORKSPACE="wiv-synapse-billing"
STORAGE_ACCOUNT="billingstorage77626"
RESOURCE_GROUP="wiv-rg"
SUBSCRIPTION_ID="62b32106-4b98-47ea-9ac5-4181f33ae2af"

# Function to get access token
get_token() {
    echo "🔐 Getting access token..."
    
    TOKEN_RESPONSE=$(curl -s -X POST \
        "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=$CLIENT_ID" \
        -d "client_secret=$CLIENT_SECRET" \
        -d "scope=https://dev.azuresynapse.net/.default" \
        -d "grant_type=client_credentials")
    
    ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
    
    if [ -z "$ACCESS_TOKEN" ]; then
        echo "❌ Failed to get access token"
        echo "Response: $TOKEN_RESPONSE"
        return 1
    else
        echo "✅ Access token obtained"
        return 0
    fi
}

# Function to execute Synapse query using REST API
execute_query() {
    local QUERY=$1
    
    echo "📊 Executing query via REST API..."
    
    # Synapse REST API endpoint
    API_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Synapse/workspaces/$SYNAPSE_WORKSPACE/sqlPools/Built-in/dataWarehouseUserActivities?api-version=2021-06-01"
    
    # Try to execute via management API
    RESPONSE=$(curl -s -X GET \
        "$API_URL" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json")
    
    echo "Response: $RESPONSE"
}

# Alternative: Use Azure CLI if available
query_with_az_cli() {
    echo ""
    echo "📊 Querying using Azure CLI..."
    
    # Login with service principal
    az login --service-principal \
        --username "$CLIENT_ID" \
        --password "$CLIENT_SECRET" \
        --tenant "$TENANT_ID" \
        --output none 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ Logged in successfully"
        
        # Create a SQL script in Synapse
        QUERY='SELECT TOP 10 * FROM OPENROWSET(BULK '\''https://billingstorage77626.blob.core.windows.net/billing-exports/DailyBillingExport*.csv'\'', FORMAT = '\''CSV'\'', PARSER_VERSION = '\''2.0'\'', FIRSTROW = 2) WITH (Date NVARCHAR(100), ServiceFamily NVARCHAR(100), ResourceGroup NVARCHAR(100), CostInUSD NVARCHAR(50)) AS BillingData'
        
        echo "Creating SQL script in Synapse..."
        
        # Create SQL script via REST API
        SCRIPT_NAME="BillingQuery_$(date +%s)"
        
        az rest --method PUT \
            --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Synapse/workspaces/$SYNAPSE_WORKSPACE/sqlScripts/$SCRIPT_NAME?api-version=2021-06-01-preview" \
            --body "{
                \"properties\": {
                    \"content\": {
                        \"query\": \"$QUERY\",
                        \"metadata\": {
                            \"language\": \"sql\"
                        }
                    },
                    \"type\": \"SqlQuery\"
                }
            }" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "✅ SQL script created: $SCRIPT_NAME"
            echo "📝 Go to Synapse Studio to run the script"
        else
            echo "⚠️ Could not create SQL script automatically"
        fi
    else
        echo "❌ Azure CLI login failed"
    fi
}

# Main execution
echo "Configuration:"
echo "  Workspace: $SYNAPSE_WORKSPACE"
echo "  Storage: $STORAGE_ACCOUNT"
echo "======================================"

# Get access token
get_token

if [ $? -eq 0 ]; then
    # Try to execute query
    TEST_QUERY="SELECT GETDATE() as CurrentTime"
    execute_query "$TEST_QUERY"
fi

# Try Azure CLI method
query_with_az_cli

echo ""
echo "======================================"
echo "📝 To query remotely, you can:"
echo "1. Use Synapse Studio web interface (easiest)"
echo "2. Use Azure Data Studio with Synapse connection"
echo "3. Use Power BI with Synapse connector"
echo "4. Use the following connection string in any SQL client:"
echo ""
echo "Server: $SYNAPSE_WORKSPACE.sql.azuresynapse.net"
echo "Database: master"
echo "Authentication: Azure Active Directory"
echo "======================================"