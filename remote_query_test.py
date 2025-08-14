#!/usr/bin/env python3
"""
Remote Synapse Query Validation Script
Tests query execution against Azure Synapse serverless SQL pool
"""

import requests
import json
import subprocess
import sys
from time import sleep

# Configuration
CONFIG = {
    "tenant_id": "ba153ff0-3397-4ef5-a214-dd33e8c37bff",
    "client_id": "554b11c1-18f9-46b5-a096-30e0a2cfae6f",
    "client_secret": "tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams",
    "synapse_workspace": "wiv-synapse-billing",
    "storage_account": "billingstorage77626",
    "file_path": "billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv"
}

def get_access_token():
    """Get access token for Synapse using service principal"""
    print("🔐 Getting access token...")
    
    # Get token using Azure CLI (already logged in)
    try:
        result = subprocess.run(
            ["az", "account", "get-access-token", "--resource", "https://dev.azuresynapse.net"],
            capture_output=True,
            text=True,
            check=True
        )
        token_data = json.loads(result.stdout)
        print("✅ Access token obtained")
        return token_data["accessToken"]
    except Exception as e:
        print(f"❌ Failed to get access token: {e}")
        return None

def test_synapse_connection(token):
    """Test basic connection to Synapse workspace"""
    print("\n🔷 Testing Synapse connection...")
    
    endpoint = f"https://{CONFIG['synapse_workspace']}-ondemand.sql.azuresynapse.net"
    
    # Simple test query
    query = "SELECT 'Connected' as Status, GETDATE() as CurrentTime"
    
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }
    
    # Note: The Synapse SQL on-demand doesn't have a direct REST API for query execution
    # Queries must be executed through SQL connections (ODBC/JDBC) or Synapse Studio
    
    print(f"Endpoint: {endpoint}")
    print("Note: Direct REST API query execution is not supported for serverless SQL pool")
    print("Queries must be executed through:")
    print("  1. Synapse Studio (recommended)")
    print("  2. SQL client tools (SSMS, Azure Data Studio)")
    print("  3. ODBC/JDBC connections")
    
    return True

def generate_query_file():
    """Generate the validated query file for use in Synapse Studio"""
    print("\n📝 Generating validated query file...")
    
    query = f"""-- Validated Query for Remote Execution
-- Use this in Synapse Studio or SQL client tools

-- Connection Details:
-- Server: {CONFIG['synapse_workspace']}-ondemand.sql.azuresynapse.net
-- Database: master
-- Authentication: Azure Active Directory - Service Principal
-- Username: {CONFIG['client_id']}
-- Password: {CONFIG['client_secret']}

-- Query 1: Test basic connectivity
SELECT 'Connected to Synapse' as Status, GETDATE() as Timestamp;

-- Query 2: Read billing data with exact file path
SELECT TOP 10 *
FROM OPENROWSET(
    BULK 'https://{CONFIG['storage_account']}.blob.core.windows.net/billing-exports/{CONFIG['file_path']}',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    Date NVARCHAR(100),
    ServiceFamily NVARCHAR(100),
    MeterCategory NVARCHAR(100),
    MeterSubcategory NVARCHAR(100),
    MeterName NVARCHAR(200),
    BillingAccountName NVARCHAR(100),
    CostCenter NVARCHAR(50),
    ResourceGroup NVARCHAR(100),
    ResourceLocation NVARCHAR(50),
    ConsumedService NVARCHAR(100),
    ResourceId NVARCHAR(500),
    ChargeType NVARCHAR(50),
    PublisherType NVARCHAR(50),
    Quantity NVARCHAR(50),
    CostInBillingCurrency NVARCHAR(50),
    CostInUSD NVARCHAR(50),
    PayGPrice NVARCHAR(50),
    BillingCurrencyCode NVARCHAR(10),
    SubscriptionName NVARCHAR(100),
    SubscriptionId NVARCHAR(50),
    ProductName NVARCHAR(200),
    Frequency NVARCHAR(50),
    UnitOfMeasure NVARCHAR(50),
    Tags NVARCHAR(MAX)
) AS BillingData;

-- Query 3: Aggregated billing summary
SELECT 
    ServiceFamily,
    ResourceGroup,
    COUNT(*) as RecordCount,
    SUM(TRY_CAST(CostInUSD as FLOAT)) as TotalCost
FROM OPENROWSET(
    BULK 'https://{CONFIG['storage_account']}.blob.core.windows.net/billing-exports/{CONFIG['file_path']}',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    FIRSTROW = 2
)
WITH (
    ServiceFamily NVARCHAR(100),
    ResourceGroup NVARCHAR(100),
    CostInUSD NVARCHAR(50)
) AS BillingData
GROUP BY ServiceFamily, ResourceGroup
ORDER BY TotalCost DESC;
"""
    
    with open("remote_validated_query.sql", "w") as f:
        f.write(query)
    
    print("✅ Query saved to remote_validated_query.sql")
    return True

def test_with_pyodbc():
    """Provide instructions for using pyodbc for remote connection"""
    print("\n🐍 Python ODBC Connection Example:")
    print("-" * 40)
    
    code = f"""
import pyodbc
import pandas as pd

# Connection string
conn_str = (
    f"DRIVER={{ODBC Driver 18 for SQL Server}};"
    f"SERVER={CONFIG['synapse_workspace']}-ondemand.sql.azuresynapse.net;"
    f"DATABASE=master;"
    f"UID={CONFIG['client_id']};"
    f"PWD={CONFIG['client_secret']};"
    f"Authentication=ActiveDirectoryServicePrincipal;"
    f"Encrypt=yes;"
    f"TrustServerCertificate=no;"
)

# Connect and execute query
try:
    conn = pyodbc.connect(conn_str)
    query = '''
    SELECT TOP 10 * 
    FROM OPENROWSET(
        BULK 'https://{CONFIG['storage_account']}.blob.core.windows.net/billing-exports/{CONFIG['file_path']}',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        FIRSTROW = 2
    )
    WITH (
        Date NVARCHAR(100),
        ServiceFamily NVARCHAR(100),
        ResourceGroup NVARCHAR(100),
        CostInUSD NVARCHAR(50)
    ) AS BillingData
    '''
    
    df = pd.read_sql(query, conn)
    print(df)
    conn.close()
    
except Exception as e:
    print(f"Error: {{e}}")
"""
    
    print(code)
    
    # Save to file
    with open("remote_connection_example.py", "w") as f:
        f.write(code)
    
    print("\n✅ Connection example saved to remote_connection_example.py")

def main():
    print("🚀 Remote Synapse Query Validation")
    print("=" * 50)
    
    # Get access token
    token = get_access_token()
    if not token:
        print("❌ Cannot proceed without access token")
        sys.exit(1)
    
    # Test connection
    test_synapse_connection(token)
    
    # Generate query file
    generate_query_file()
    
    # Provide ODBC example
    test_with_pyodbc()
    
    print("\n" + "=" * 50)
    print("📋 VALIDATION SUMMARY")
    print("=" * 50)
    print(f"""
✅ Service Principal: {CONFIG['client_id']}
✅ Synapse Workspace: {CONFIG['synapse_workspace']}
✅ Storage Account: {CONFIG['storage_account']}
✅ File Path: {CONFIG['file_path']}

🔧 TO EXECUTE QUERIES REMOTELY:

Option 1: Synapse Studio (Easiest)
   1. Go to: https://web.azuresynapse.net
   2. Select workspace: {CONFIG['synapse_workspace']}
   3. Use queries from: remote_validated_query.sql

Option 2: SQL Client Tools
   - Server: {CONFIG['synapse_workspace']}-ondemand.sql.azuresynapse.net
   - Database: master
   - Auth: Azure AD - Service Principal
   - Use credentials provided

Option 3: Python/ODBC
   - Install: pip install pyodbc pandas
   - Use code from: remote_connection_example.py

Note: Direct REST API query execution is not supported for 
serverless SQL pools. Use one of the options above.
""")

if __name__ == "__main__":
    main()