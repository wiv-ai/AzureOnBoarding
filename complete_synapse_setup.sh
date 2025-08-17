#!/bin/bash

# Complete Synapse Setup Script
# This finishes the setup that requires SQL execution

echo "🔧 Completing Synapse Setup..."
echo "================================"

# Configuration from your deployment
WORKSPACE="wiv-synapse-billing"
CLIENT_ID="554b11c1-18f9-46b5-a096-30e0a2cfae6f"
CLIENT_SECRET="tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams"
STORAGE_ACCOUNT="billingstorage19035"
MASTER_KEY_PASSWORD="P@ssw0rd19093!"

echo "📊 Creating BillingAnalytics database and view..."

# Method 1: Try using Azure CLI Synapse SQL command
echo "Attempting to create database via Azure CLI..."

# Create database
az synapse sql script create \
    --workspace-name "$WORKSPACE" \
    --name "CreateBillingDatabase" \
    --file /dev/stdin <<EOF
CREATE DATABASE IF NOT EXISTS BillingAnalytics;
EOF

# Create and execute the view creation script
az synapse sql script create \
    --workspace-name "$WORKSPACE" \
    --name "CreateBillingView" \
    --file /dev/stdin <<'EOF'
USE BillingAnalytics;

-- Create master key if not exists
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$MASTER_KEY_PASSWORD';
END

-- Drop old view if exists
IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingData')
    DROP VIEW BillingData;

-- Create improved view with automatic deduplication
CREATE VIEW BillingData AS
WITH LatestExport AS (
    SELECT MAX(filepath(1)) as LatestPath
    FROM OPENROWSET(
        BULK 'abfss://billing-exports@$STORAGE_ACCOUNT.dfs.core.windows.net/billing-data/DailyBillingExport/*/*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        FIRSTROW = 2
    ) AS files
)
SELECT *
FROM OPENROWSET(
    BULK 'abfss://billing-exports@$STORAGE_ACCOUNT.dfs.core.windows.net/billing-data/DailyBillingExport/*/*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    date NVARCHAR(100),
    serviceFamily NVARCHAR(200),
    meterCategory NVARCHAR(200),
    meterSubCategory NVARCHAR(200),
    meterName NVARCHAR(500),
    billingAccountName NVARCHAR(200),
    costCenter NVARCHAR(100),
    resourceGroupName NVARCHAR(200),
    resourceLocation NVARCHAR(100),
    consumedService NVARCHAR(200),
    ResourceId NVARCHAR(1000),
    chargeType NVARCHAR(100),
    publisherType NVARCHAR(100),
    quantity NVARCHAR(100),
    costInBillingCurrency NVARCHAR(100),
    costInUsd NVARCHAR(100),
    PayGPrice NVARCHAR(100),
    billingCurrency NVARCHAR(10),
    subscriptionName NVARCHAR(200),
    SubscriptionId NVARCHAR(100),
    ProductName NVARCHAR(500),
    frequency NVARCHAR(100),
    unitOfMeasure NVARCHAR(100),
    tags NVARCHAR(4000)
) AS BillingData
WHERE filepath(1) = (SELECT LatestPath FROM LatestExport);
EOF

# Execute the scripts
echo "🚀 Executing SQL scripts..."
az synapse sql script start \
    --workspace-name "$WORKSPACE" \
    --name "CreateBillingDatabase" \
    --spark-pool-name "Built-in"

sleep 5

az synapse sql script start \
    --workspace-name "$WORKSPACE" \
    --name "CreateBillingView" \
    --spark-pool-name "Built-in"

echo ""
echo "✅ Setup Complete!"
echo "=================="
echo ""
echo "Test your setup with this query in Synapse Studio:"
echo "  SELECT TOP 10 * FROM BillingAnalytics.dbo.BillingData"
echo ""
echo "Or test with curl:"
echo "  curl -X POST https://$WORKSPACE-ondemand.sql.azuresynapse.net/sql/query \\"
echo "    -H 'Authorization: Bearer <token>' \\"
echo "    -d '{\"query\": \"SELECT COUNT(*) FROM BillingAnalytics.dbo.BillingData\"}'"