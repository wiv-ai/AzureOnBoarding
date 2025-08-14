#!/usr/bin/env python3
import pyodbc

config = {
    'workspace_name': 'wiv-synapse-billing',
    'client_id': '554b11c1-18f9-46b5-a096-30e0a2cfae6f',
    'client_secret': 'tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams',
    'storage_account': 'billingstorage85409'
}

billing_conn_str = f"""
DRIVER={{ODBC Driver 18 for SQL Server}};
SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;
DATABASE=BillingAnalytics;
UID={config['client_id']};
PWD={config['client_secret']};
Authentication=ActiveDirectoryServicePrincipal;
Encrypt=yes;
TrustServerCertificate=no;
"""

print("Testing different Managed Identity approaches...")
try:
    conn = pyodbc.connect(billing_conn_str, autocommit=True)
    cursor = conn.cursor()
    
    # Test 1: Direct OPENROWSET with abfss protocol (Data Lake Gen2)
    print("\n1. Testing with abfss:// protocol...")
    try:
        query = f"""
        SELECT TOP 1 * FROM OPENROWSET(
            BULK 'abfss://billing-exports@{config['storage_account']}.dfs.core.windows.net/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_91f1e7fa-40bd-460d-b22c-f72cb6aaf761.csv',
            FORMAT = 'CSV',
            PARSER_VERSION = '2.0',
            FIRSTROW = 2
        ) WITH (
            date NVARCHAR(100)
        ) AS test
        """
        cursor.execute(query)
        print("✅ abfss:// protocol works with Managed Identity!")
    except Exception as e:
        print(f"❌ abfss:// failed: {str(e)[:100]}")
    
    # Test 2: Check current user context
    print("\n2. Checking authentication context...")
    cursor.execute("SELECT SUSER_NAME() as CurrentUser, SUSER_SNAME() as CurrentPrincipal")
    row = cursor.fetchone()
    print(f"   Current User: {row[0]}")
    print(f"   Principal: {row[1]}")
    
    # Test 3: List role assignments
    print("\n3. Checking storage account permissions...")
    import subprocess
    result = subprocess.run([
        'az', 'role', 'assignment', 'list',
        '--assignee', '82e3243d-948d-48ce-8708-d635fb79256d',
        '--scope', f"/subscriptions/7f6dc2fe-6841-4aca-b2d3-d6a00e96e99f/resourceGroups/wiv-rg/providers/Microsoft.Storage/storageAccounts/{config['storage_account']}",
        '--query', "[].roleDefinitionName",
        '--output', 'tsv'
    ], capture_output=True, text=True)
    
    roles = result.stdout.strip()
    print(f"   Synapse Managed Identity roles: {roles}")
    
    cursor.close()
    conn.close()
    
except Exception as e:
    print(f"Error: {e}")
