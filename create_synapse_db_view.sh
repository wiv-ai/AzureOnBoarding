#!/bin/bash
# Fix script for Synapse database and view creation

echo "Azure Synapse Database Creation Fix"
echo "===================================="

# Get configuration
if [ -f "synapse_config.py" ]; then
    SYNAPSE_WORKSPACE=$(grep "workspace_name" synapse_config.py | cut -d"'" -f4)
    STORAGE_ACCOUNT=$(grep "storage_account" synapse_config.py | cut -d"'" -f4)
    CONTAINER=$(grep "container" synapse_config.py | grep -v storage | cut -d"'" -f4)
    EXPORT_PATH=$(grep "export_path" synapse_config.py | cut -d"'" -f4)
else
    read -p "Synapse Workspace: " SYNAPSE_WORKSPACE
    read -p "Storage Account: " STORAGE_ACCOUNT
    read -p "Container: " CONTAINER
    read -p "Export Path: " EXPORT_PATH
fi

# Get token
TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv)

if [ -z "$TOKEN" ]; then
    echo "Error: No token. Run: az login"
    exit 1
fi

echo "Creating database and view..."

# Create database
curl -s -X POST \
    "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/master/query" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"query": "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = '\''BillingAnalytics'\'') CREATE DATABASE BillingAnalytics"}'

sleep 10

# Create user and permissions
curl -s -X POST \
    "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"query": "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '\''wiv_account'\'') CREATE USER [wiv_account] FROM EXTERNAL PROVIDER; ALTER ROLE db_datareader ADD MEMBER [wiv_account]"}'

echo "Done! Database should be created."
