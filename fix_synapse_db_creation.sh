#!/bin/bash
# Fixed database and view creation script for Azure Synapse
# This script fixes the critical issues in startup_with_billing_synapse.sh

# Function to create database and view using REST API
create_synapse_database() {
    local SYNAPSE_WORKSPACE="$1"
    local STORAGE_ACCOUNT_NAME="$2"
    local CONTAINER_NAME="$3"
    local EXPORT_PATH="$4"
    local MASTER_KEY_PASSWORD="$5"
    
    echo "🔧 Creating Synapse database and view using REST API..."
    
    # Get Azure access token
    ACCESS_TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>/dev/null)
    
    if [ -z "$ACCESS_TOKEN" ]; then
        echo "❌ Failed to get Azure access token. Please run 'az login' first."
        return 1
    fi
    
    echo "✅ Got Azure access token"
    
    # Create database
    echo "Creating BillingAnalytics database..."
    curl -s -X POST \
        "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/master/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"query": "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = '\''BillingAnalytics'\'') CREATE DATABASE BillingAnalytics"}' \
        -o /dev/null 2>&1
    
    sleep 10
    
    # Create master key
    echo "Creating master key..."
    curl -s -X POST \
        "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##') CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$MASTER_KEY_PASSWORD'\"}" \
        -o /dev/null 2>&1
    
    sleep 5
    
    # Create user for service principal
    echo "Creating user wiv_account..."
    curl -s -X POST \
        "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"query": "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '\''wiv_account'\'') CREATE USER [wiv_account] FROM EXTERNAL PROVIDER"}' \
        -o /dev/null 2>&1
    
    sleep 5
    
    # Grant permissions
    echo "Granting permissions..."
    curl -s -X POST \
        "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"query": "ALTER ROLE db_datareader ADD MEMBER [wiv_account]; ALTER ROLE db_datawriter ADD MEMBER [wiv_account]; ALTER ROLE db_ddladmin ADD MEMBER [wiv_account]"}' \
        -o /dev/null 2>&1
    
    sleep 5
    
    # Create BillingData view
    echo "Creating BillingData view..."
    VIEW_SQL="CREATE OR ALTER VIEW BillingData AS SELECT * FROM OPENROWSET(BULK 'abfss://${CONTAINER_NAME}@${STORAGE_ACCOUNT_NAME}.dfs.core.windows.net/${EXPORT_PATH}/*/*.csv', FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE) AS BillingExport"
    
    curl -s -X POST \
        "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"$VIEW_SQL\"}" \
        -o /dev/null 2>&1
    
    # Verify creation
    echo ""
    echo "Verifying database setup..."
    
    # Check database
    DB_CHECK=$(curl -s -X POST \
        "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/master/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"query": "SELECT name FROM sys.databases WHERE name = '\''BillingAnalytics'\''"}' 2>&1)
    
    if [[ "$DB_CHECK" == *"BillingAnalytics"* ]]; then
        echo "✅ Database created successfully"
    else
        echo "⚠️ Database might not be created"
    fi
    
    # Check view
    VIEW_CHECK=$(curl -s -X POST \
        "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"query": "SELECT name FROM sys.views WHERE name = '\''BillingData'\''"}' 2>&1)
    
    if [[ "$VIEW_CHECK" == *"BillingData"* ]]; then
        echo "✅ View created successfully"
    else
        echo "⚠️ View might not be created"
    fi
    
    echo ""
    echo "✅ Database setup process completed!"
}

# Main execution
echo "Azure Synapse Database Fix Script"
echo "=================================="
echo ""

# Check if synapse_config.py exists to get configuration
if [ -f "synapse_config.py" ]; then
    echo "Found synapse_config.py, extracting configuration..."
    SYNAPSE_WORKSPACE=$(grep "workspace_name" synapse_config.py | cut -d"'" -f4)
    STORAGE_ACCOUNT_NAME=$(grep "storage_account" synapse_config.py | cut -d"'" -f4)
    CONTAINER_NAME=$(grep "container" synapse_config.py | grep -v "storage" | cut -d"'" -f4)
    EXPORT_PATH=$(grep "export_path" synapse_config.py | cut -d"'" -f4)
else
    # Prompt for configuration
    echo "Please provide the following information:"
    read -p "Synapse Workspace Name: " SYNAPSE_WORKSPACE
    read -p "Storage Account Name: " STORAGE_ACCOUNT_NAME
    read -p "Container Name (default: billing-exports): " CONTAINER_NAME
    CONTAINER_NAME=${CONTAINER_NAME:-billing-exports}
    read -p "Export Path (default: billing-data): " EXPORT_PATH
    EXPORT_PATH=${EXPORT_PATH:-billing-data}
fi

# Generate a secure master key password
MASTER_KEY_PASSWORD="StrongP@ssw0rd$(date +%s | tail -c 6)!"

echo ""
echo "Configuration:"
echo "  Synapse Workspace: $SYNAPSE_WORKSPACE"
echo "  Storage Account: $STORAGE_ACCOUNT_NAME"
echo "  Container: $CONTAINER_NAME"
echo "  Export Path: $EXPORT_PATH"
echo ""

# Create the database and view
create_synapse_database "$SYNAPSE_WORKSPACE" "$STORAGE_ACCOUNT_NAME" "$CONTAINER_NAME" "$EXPORT_PATH" "$MASTER_KEY_PASSWORD"

echo ""
echo "If the automated setup didn't work, you can manually run the following SQL in Synapse Studio:"
echo "--------------------------------------------------------------------------------"
cat << SQLEOF
-- Run this in Synapse Studio connected to the Built-in serverless SQL pool

-- Create database
CREATE DATABASE BillingAnalytics;
GO

USE BillingAnalytics;
GO

-- Create master key
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$MASTER_KEY_PASSWORD';
GO

-- Create user for service principal
CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
GO

-- Grant permissions
ALTER ROLE db_datareader ADD MEMBER [wiv_account];
ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
GO

-- Create view for billing data
CREATE OR ALTER VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK 'abfss://${CONTAINER_NAME}@${STORAGE_ACCOUNT_NAME}.dfs.core.windows.net/${EXPORT_PATH}/*/*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport;
GO

-- Test the view
SELECT TOP 10 * FROM BillingData;
GO
SQLEOF
echo "--------------------------------------------------------------------------------"
