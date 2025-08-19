#!/usr/bin/env python3
"""
Simple connection test with detailed error reporting
"""

import pyodbc
import sys
from synapse_config import SYNAPSE_CONFIG as config

print("Testing connection to Synapse...")
print(f"Workspace: {config['workspace_name']}")
print(f"Database: {config['database_name']}")
print(f"Client ID: {config['client_id']}")
print(f"Tenant ID: {config['tenant_id']}")

# Try different connection string variations
connection_strings = [
    # Standard connection string
    {
        "name": "Standard with Service Principal",
        "string": f"DRIVER={{ODBC Driver 18 for SQL Server}};"
                 f"SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;"
                 f"DATABASE={config['database_name']};"
                 f"UID={config['client_id']};"
                 f"PWD={config['client_secret']};"
                 f"Authentication=ActiveDirectoryServicePrincipal;"
                 f"Encrypt=yes;"
                 f"TrustServerCertificate=no;"
    },
    # With port
    {
        "name": "With explicit port 1433",
        "string": f"DRIVER={{ODBC Driver 18 for SQL Server}};"
                 f"SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net,1433;"
                 f"DATABASE={config['database_name']};"
                 f"UID={config['client_id']};"
                 f"PWD={config['client_secret']};"
                 f"Authentication=ActiveDirectoryServicePrincipal;"
                 f"Encrypt=yes;"
                 f"TrustServerCertificate=no;"
    },
    # With trust certificate (less secure but sometimes needed)
    {
        "name": "With TrustServerCertificate=yes",
        "string": f"DRIVER={{ODBC Driver 18 for SQL Server}};"
                 f"SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;"
                 f"DATABASE={config['database_name']};"
                 f"UID={config['client_id']};"
                 f"PWD={config['client_secret']};"
                 f"Authentication=ActiveDirectoryServicePrincipal;"
                 f"Encrypt=yes;"
                 f"TrustServerCertificate=yes;"
    }
]

for conn_config in connection_strings:
    print(f"\n🔌 Trying: {conn_config['name']}...")
    try:
        conn = pyodbc.connect(conn_config['string'], timeout=15)
        cursor = conn.cursor()
        cursor.execute("SELECT DB_NAME() as db, @@VERSION as version")
        row = cursor.fetchone()
        print(f"✅ SUCCESS! Connected to: {row.db}")
        print(f"   Server version: {row.version[:50]}...")
        
        # If successful, check for views
        cursor.execute("""
            SELECT COUNT(*) as view_count FROM sys.views
        """)
        view_count = cursor.fetchone()
        print(f"   Number of views in database: {view_count.view_count}")
        
        cursor.execute("""
            SELECT COUNT(*) as table_count FROM sys.tables
        """)
        table_count = cursor.fetchone()
        print(f"   Number of tables in database: {table_count.table_count}")
        
        cursor.close()
        conn.close()
        break
        
    except pyodbc.Error as e:
        print(f"❌ Failed: {str(e)[:150]}")
        if "Login timeout expired" in str(e):
            print("   → Network connectivity issue or firewall blocking")
        elif "Login failed" in str(e):
            print("   → Authentication issue - check credentials")
        elif "Invalid connection string" in str(e):
            print("   → Connection string format issue")
    except Exception as e:
        print(f"❌ Unexpected error: {str(e)[:150]}")

print("\n" + "="*50)
print("If all connections failed, check:")
print("1. Firewall rules in Synapse workspace")
print("2. Service principal has correct permissions")
print("3. Workspace and database names are correct")
print("4. Network connectivity from this location")