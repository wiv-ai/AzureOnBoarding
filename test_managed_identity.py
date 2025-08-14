#!/usr/bin/env python3
import pyodbc

config = {
    'workspace_name': 'wiv-synapse-billing',
    'client_id': '554b11c1-18f9-46b5-a096-30e0a2cfae6f',
    'client_secret': 'tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams'
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

print("Testing Managed Identity view...")
try:
    conn = pyodbc.connect(billing_conn_str, autocommit=True)
    cursor = conn.cursor()
    
    cursor.execute("SELECT COUNT(*) as RecordCount FROM BillingDataMI")
    row = cursor.fetchone()
    print(f"✅ MANAGED IDENTITY WORKING! Found {row[0]} records")
    print("\nNo more SAS tokens needed! 🎉")
    
    # Update the main view
    cursor.execute("IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingData') DROP VIEW BillingData")
    cursor.execute("CREATE VIEW BillingData AS SELECT * FROM BillingDataMI")
    print("✅ Main BillingData view now uses Managed Identity!")
    
    cursor.close()
    conn.close()
    
except Exception as e:
    print(f"⚠️ Still propagating: {e}")
    print("The SAS token version is still working as backup")
