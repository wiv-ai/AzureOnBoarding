#!/usr/bin/env python3
"""
Script to check what tables and views exist in the Synapse database
"""

import pyodbc
import sys

# Import configuration
try:
    from synapse_config import SYNAPSE_CONFIG
    config = SYNAPSE_CONFIG
    print("✅ Using configuration from synapse_config.py")
except ImportError:
    print("❌ synapse_config.py not found. Please create it with your credentials.")
    print("   See synapse_config.py.example for the format.")
    sys.exit(1)

print(f"\n📊 Checking Database Objects in Synapse")
print("=" * 50)
print(f"Workspace: {config['workspace_name']}")
print(f"Database: {config.get('database_name', 'BillingAnalytics')}")

# Build connection string
conn_str = (
    f"DRIVER={{ODBC Driver 18 for SQL Server}};"
    f"SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;"
    f"DATABASE={config.get('database_name', 'BillingAnalytics')};"
    f"UID={config['client_id']};"
    f"PWD={config['client_secret']};"
    f"Authentication=ActiveDirectoryServicePrincipal;"
    f"Encrypt=yes;"
    f"TrustServerCertificate=no;"
)

try:
    print("\n🔌 Connecting to Synapse...")
    conn = pyodbc.connect(conn_str)
    cursor = conn.cursor()
    print("✅ Connected successfully")
    
    # Check for views
    print("\n📋 Views in the database:")
    print("-" * 30)
    cursor.execute("""
        SELECT 
            schema_name(v.schema_id) as SchemaName,
            v.name as ViewName,
            v.create_date as CreatedDate,
            v.modify_date as ModifiedDate
        FROM sys.views v
        ORDER BY SchemaName, ViewName
    """)
    
    views = cursor.fetchall()
    if views:
        for view in views:
            print(f"  [{view.SchemaName}].[{view.ViewName}]")
            print(f"    Created: {view.CreatedDate}, Modified: {view.ModifiedDate}")
    else:
        print("  No views found")
    
    # Check for tables
    print("\n📋 Tables in the database:")
    print("-" * 30)
    cursor.execute("""
        SELECT 
            schema_name(t.schema_id) as SchemaName,
            t.name as TableName,
            t.create_date as CreatedDate,
            t.modify_date as ModifiedDate
        FROM sys.tables t
        ORDER BY SchemaName, TableName
    """)
    
    tables = cursor.fetchall()
    if tables:
        for table in tables:
            print(f"  [{table.SchemaName}].[{table.TableName}]")
            print(f"    Created: {table.CreatedDate}, Modified: {table.ModifiedDate}")
    else:
        print("  No tables found")
    
    # Check for external tables (often used in Synapse for data lake access)
    print("\n📋 External Tables in the database:")
    print("-" * 30)
    cursor.execute("""
        SELECT 
            schema_name(t.schema_id) as SchemaName,
            t.name as TableName,
            t.create_date as CreatedDate
        FROM sys.external_tables t
        ORDER BY SchemaName, TableName
    """)
    
    ext_tables = cursor.fetchall()
    if ext_tables:
        for table in ext_tables:
            print(f"  [{table.SchemaName}].[{table.TableName}]")
            print(f"    Created: {table.CreatedDate}")
    else:
        print("  No external tables found")
    
    # Check schemas
    print("\n📋 Schemas in the database:")
    print("-" * 30)
    cursor.execute("""
        SELECT 
            s.name as SchemaName,
            p.name as Owner
        FROM sys.schemas s
        LEFT JOIN sys.database_principals p ON s.principal_id = p.principal_id
        WHERE s.name NOT IN ('sys', 'INFORMATION_SCHEMA', 'guest')
        ORDER BY SchemaName
    """)
    
    schemas = cursor.fetchall()
    if schemas:
        for schema in schemas:
            print(f"  {schema.SchemaName} (Owner: {schema.Owner})")
    else:
        print("  Only system schemas found")
    
    # Check if there are any objects with 'billing' in the name
    print("\n🔍 Objects containing 'billing' in the name:")
    print("-" * 30)
    cursor.execute("""
        SELECT 
            type_desc as ObjectType,
            schema_name(schema_id) as SchemaName,
            name as ObjectName
        FROM sys.objects
        WHERE LOWER(name) LIKE '%billing%'
        ORDER BY ObjectType, SchemaName, ObjectName
    """)
    
    billing_objects = cursor.fetchall()
    if billing_objects:
        for obj in billing_objects:
            print(f"  {obj.ObjectType}: [{obj.SchemaName}].[{obj.ObjectName}]")
    else:
        print("  No objects with 'billing' in the name found")
    
    cursor.close()
    conn.close()
    
    print("\n" + "=" * 50)
    print("✅ Database exploration complete")
    
except Exception as e:
    print(f"\n❌ Error: {str(e)}")
    print("\nPossible issues:")
    print("1. Service principal credentials may be incorrect")
    print("2. Synapse workspace may not be accessible")
    print("3. Database may not exist")
    print("4. Firewall rules may be blocking access")
    sys.exit(1)