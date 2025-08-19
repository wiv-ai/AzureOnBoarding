#!/usr/bin/env python3
"""
Test connection with extended timeout and detailed diagnostics
"""

import pyodbc
import time
from synapse_config import SYNAPSE_CONFIG as config

print("Testing Synapse connection with extended timeout...")
print(f"Workspace: {config['workspace_name']}")
print(f"Endpoint: {config['workspace_name']}-ondemand.sql.azuresynapse.net")
print(f"Database: {config['database_name']}")
print("-" * 50)

# Connection string
conn_str = (
    f"DRIVER={{ODBC Driver 18 for SQL Server}};"
    f"SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;"
    f"DATABASE={config['database_name']};"
    f"UID={config['client_id']};"
    f"PWD={config['client_secret']};"
    f"Authentication=ActiveDirectoryServicePrincipal;"
    f"Encrypt=yes;"
    f"TrustServerCertificate=no;"
    f"Connection Timeout=60;"  # Extended timeout
)

print("\nAttempting connection (60 second timeout)...")
start_time = time.time()

try:
    conn = pyodbc.connect(conn_str)
    elapsed = time.time() - start_time
    print(f"✅ Connected successfully in {elapsed:.2f} seconds!")
    
    cursor = conn.cursor()
    
    # Test query
    cursor.execute("SELECT DB_NAME() as db, CURRENT_TIMESTAMP as time")
    row = cursor.fetchone()
    print(f"   Database: {row.db}")
    print(f"   Server time: {row.time}")
    
    # Check for any objects
    cursor.execute("""
        SELECT 
            'Views' as ObjectType, COUNT(*) as Count FROM sys.views
        UNION ALL
        SELECT 'Tables', COUNT(*) FROM sys.tables
        UNION ALL
        SELECT 'External Tables', COUNT(*) FROM sys.external_tables
        UNION ALL
        SELECT 'Schemas', COUNT(*) FROM sys.schemas WHERE schema_id > 4
    """)
    
    print("\nDatabase objects:")
    for row in cursor:
        print(f"   {row.ObjectType}: {row.Count}")
    
    # List any non-system schemas
    cursor.execute("""
        SELECT name FROM sys.schemas 
        WHERE schema_id > 4 
        ORDER BY name
    """)
    schemas = cursor.fetchall()
    if schemas:
        print("\nUser schemas:")
        for schema in schemas:
            print(f"   - {schema.name}")
    
    cursor.close()
    conn.close()
    
except pyodbc.OperationalError as e:
    elapsed = time.time() - start_time
    print(f"❌ Connection failed after {elapsed:.2f} seconds")
    error_msg = str(e)
    
    if "Login timeout expired" in error_msg:
        print("\n⚠️  TIMEOUT: Cannot reach the SQL endpoint")
        print("Possible causes:")
        print("1. Firewall is blocking your current IP address")
        print("2. Synapse workspace networking is set to 'Disabled'")
        print("3. Network connectivity issue from this location")
        print("\nTo fix:")
        print("1. Go to Azure Portal > Your Synapse Workspace")
        print("2. Navigate to Networking > Firewall rules")
        print("3. Add your current IP address or enable 'Allow Azure services'")
        
    elif "Login failed" in error_msg:
        print("\n⚠️  AUTHENTICATION FAILED")
        print("The service principal credentials are incorrect or don't have access")
        
    else:
        print(f"\nError details: {error_msg}")
        
except Exception as e:
    print(f"❌ Unexpected error: {str(e)}")

print("\n" + "=" * 50)