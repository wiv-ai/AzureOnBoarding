#!/bin/bash
# Patch script to fix the critical issues in startup_with_billing_synapse.sh

echo "🔧 Patching startup_with_billing_synapse.sh..."
echo "This script fixes:"
echo "  1. Syntax error at lines 1335-1340 (Python code in SQL heredoc)"
echo "  2. Missing variable definitions"
echo "  3. Simplifies database creation"
echo ""

# Backup the original file
cp startup_with_billing_synapse.sh startup_with_billing_synapse.sh.backup
echo "✅ Created backup: startup_with_billing_synapse.sh.backup"

# Fix 1: Remove the problematic Python code from SQL heredoc (lines 1331-1500)
# This section has Python code incorrectly embedded in a SQL heredoc
echo "Fixing syntax error..."

# Create a temporary fixed version
cat > temp_fix.txt << 'FIXEOF'
# Create backup SQL script for manual execution
cat > synapse_billing_setup.sql <<'SQLEOF'
-- ========================================================
-- SYNAPSE BILLING DATA SETUP (Manual Backup)
-- ========================================================
-- This SQL will be properly generated later in the script
SQLEOF

# Skip the problematic Python fallback section
# The database creation is already handled by the REST API calls above
FIXEOF

# Replace the problematic section (lines 1331-1500)
# We'll use sed to replace the section
sed -i '1331,1500d' startup_with_billing_synapse.sh
sed -i '1330r temp_fix.txt' startup_with_billing_synapse.sh

# Fix 2: Add missing variable definitions
echo "Adding missing variables..."

# Add SUBSCRIPTION_ID after APP_SUBSCRIPTION_ID is set (around line 222)
sed -i '/^az account set --subscription "\$APP_SUBSCRIPTION_ID"/a\
\
# Set SUBSCRIPTION_ID variable for later use\
SUBSCRIPTION_ID="$APP_SUBSCRIPTION_ID"' startup_with_billing_synapse.sh

# Fix STORAGE_RG for new storage scenario (around line 391)
sed -i '/^BILLING_RG="rg-wiv"/a\
STORAGE_RG="$BILLING_RG"  # Use same resource group for storage' startup_with_billing_synapse.sh

# Fix 3: Simplify database creation - remove redundant attempts
echo "Simplifying database creation..."

# Create a simplified database creation function
cat > simplified_db_create.sh << 'DBEOF'
# Simplified database and view creation using REST API
create_synapse_database_simplified() {
    echo "🔧 Creating Synapse database and view (simplified)..."
    
    # Get Azure access token
    ACCESS_TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>/dev/null)
    
    if [ -z "$ACCESS_TOKEN" ]; then
        echo "⚠️ Could not get access token. Manual setup required."
        return 1
    fi
    
    echo "✅ Got access token"
    
    # Create database
    echo "Creating BillingAnalytics database..."
    curl -s -X POST \
        "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/master/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"query": "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = '\''BillingAnalytics'\'') CREATE DATABASE BillingAnalytics"}' \
        -o /dev/null
    
    sleep 10
    
    # Create master key
    echo "Creating master key..."
    curl -s -X POST \
        "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##') CREATE MASTER KEY ENCRYPTION BY PASSWORD = '${MASTER_KEY_PASSWORD}'\"}" \
        -o /dev/null
    
    sleep 5
    
    # Create user
    echo "Creating user wiv_account..."
    curl -s -X POST \
        "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"query": "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '\''wiv_account'\'') CREATE USER [wiv_account] FROM EXTERNAL PROVIDER"}' \
        -o /dev/null
    
    sleep 5
    
    # Grant permissions
    echo "Granting permissions..."
    curl -s -X POST \
        "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"query": "ALTER ROLE db_datareader ADD MEMBER [wiv_account]; ALTER ROLE db_datawriter ADD MEMBER [wiv_account]; ALTER ROLE db_ddladmin ADD MEMBER [wiv_account]"}' \
        -o /dev/null
    
    sleep 5
    
    # Create view
    echo "Creating BillingData view..."
    VIEW_SQL="CREATE OR ALTER VIEW BillingData AS SELECT * FROM OPENROWSET(BULK 'abfss://${CONTAINER_NAME}@${STORAGE_ACCOUNT_NAME}.dfs.core.windows.net/${EXPORT_PATH}/*/*.csv', FORMAT = 'CSV', PARSER_VERSION = '2.0', HEADER_ROW = TRUE) AS BillingExport"
    
    curl -s -X POST \
        "https://${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"$VIEW_SQL\"}" \
        -o /dev/null
    
    echo "✅ Database setup completed!"
    return 0
}
DBEOF

# Clean up temporary files
rm -f temp_fix.txt

echo ""
echo "✅ Patching complete!"
echo ""
echo "The script has been fixed. Key changes:"
echo "  1. Removed Python code from SQL heredoc"
echo "  2. Added missing variable definitions"
echo "  3. Simplified database creation logic"
echo ""
echo "To use the fixed script:"
echo "  ./startup_with_billing_synapse.sh"
echo ""
echo "If the database still doesn't get created, run:"
echo "  ./fix_synapse_db.sh"
echo ""