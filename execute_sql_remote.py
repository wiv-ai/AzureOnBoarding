#!/usr/bin/env python3
"""
Execute SQL commands remotely on Synapse
"""

import pyodbc
import sys
from synapse_config import SYNAPSE_CONFIG as config

def execute_sql(sql_commands, show_results=False):
    """Execute SQL commands on Synapse"""
    conn_str = (
        f"DRIVER={{ODBC Driver 18 for SQL Server}};"
        f"SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;"
        f"DATABASE={config['database_name']};"
        f"UID={config['client_id']};"
        f"PWD={config['client_secret']};"
        f"Authentication=ActiveDirectoryServicePrincipal;"
        f"Encrypt=yes;"
        f"TrustServerCertificate=no;"
    )
    
    try:
        conn = pyodbc.connect(conn_str)
        cursor = conn.cursor()
        
        # Split commands by GO statement
        commands = sql_commands.split('\nGO\n')
        
        for cmd in commands:
            cmd = cmd.strip()
            if not cmd:
                continue
                
            print(f"\n📝 Executing: {cmd[:100]}..." if len(cmd) > 100 else f"\n📝 Executing: {cmd}")
            
            try:
                cursor.execute(cmd)
                
                # If it's a SELECT query, show results
                if show_results and cmd.upper().strip().startswith('SELECT'):
                    rows = cursor.fetchall()
                    if rows:
                        for row in rows:
                            print(f"   {row}")
                    else:
                        print("   No results")
                else:
                    print("   ✅ Success")
                    
            except pyodbc.Error as e:
                print(f"   ❌ Error: {e}")
                if "already exists" not in str(e):
                    # Don't stop on "already exists" errors
                    raise
        
        conn.commit()
        cursor.close()
        conn.close()
        print("\n✅ All commands executed successfully")
        return True
        
    except Exception as e:
        print(f"\n❌ Failed to execute SQL: {e}")
        return False

# First, let's check if there's an existing billing export setup
print("🔍 Checking for existing billing export configuration...")

check_sql = """
SELECT TOP 1 
    OBJECT_SCHEMA_NAME(object_id) as SchemaName,
    name as ViewName
FROM sys.views 
WHERE name LIKE '%billing%' OR name LIKE '%cost%'
"""

execute_sql(check_sql, show_results=True)

# Now let's create a basic view that can work with any storage setup
# We'll start with a simple structure that you can customize
print("\n📦 Creating billing views...")

create_views_sql = """
-- Create a simple test view first to verify permissions
IF EXISTS (SELECT * FROM sys.views WHERE name = 'TestView')
    DROP VIEW TestView
GO

CREATE VIEW TestView AS
SELECT 
    'Test' as Status,
    GETDATE() as CreatedAt
GO

-- Now let's create the billing view structure
-- You'll need to update the storage path once we know where your billing export is
IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingDataPlaceholder')
    DROP VIEW BillingDataPlaceholder
GO

CREATE VIEW BillingDataPlaceholder AS
SELECT 
    'No billing export configured' as Message,
    'Update the BULK path in this view with your actual storage account' as Instructions,
    'Example: https://yourstorageaccount.blob.core.windows.net/billing-exports/csp-billing/*.csv' as ExamplePath
GO

-- Create a view to check what external data sources exist
IF EXISTS (SELECT * FROM sys.views WHERE name = 'ExternalDataSources')
    DROP VIEW ExternalDataSources  
GO

CREATE VIEW ExternalDataSources AS
SELECT 
    name as DataSourceName,
    type_desc as Type,
    location as Location
FROM sys.external_data_sources
"""

if execute_sql(create_views_sql):
    print("\n✅ Basic views created successfully")
    
    # Now check what was created
    print("\n📋 Checking created views...")
    check_views_sql = """
    SELECT 
        SCHEMA_NAME(schema_id) as SchemaName,
        name as ViewName,
        create_date as CreatedDate
    FROM sys.views
    WHERE create_date > DATEADD(minute, -5, GETDATE())
    ORDER BY create_date DESC
    """
    
    execute_sql(check_views_sql, show_results=True)
    
    # Check for external data sources
    print("\n🔍 Checking for external data sources (storage connections)...")
    check_external_sql = """
    SELECT * FROM ExternalDataSources
    """
    
    execute_sql(check_external_sql, show_results=True)
    
print("\n" + "="*50)
print("Next steps:")
print("1. We need to find your billing export storage account details")
print("2. Update the views with the actual storage path")
print("3. Create external table or OPENROWSET query to read the CSV files")
print("\nDo you know your billing export storage account name and container?")