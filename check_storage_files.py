#!/usr/bin/env python3
"""
Check what files exist in the billing export storage
"""

import pyodbc
from synapse_config import SYNAPSE_CONFIG as config

# Your storage configuration
STORAGE_ACCOUNT = "wivcostexports"
CONTAINER = "costexport"
EXPORT_PATH = "daily/wiv-focus-cost"

print("🔍 Checking storage for billing export files...")
print("="*60)
print(f"Storage: https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/")
print("="*60 + "\n")

# SQL to check different file patterns
sql_queries = [
    # Check for CSV files
    (
        "CSV files (*.csv)",
        f"""
        SELECT TOP 10 * FROM 
        sys.fn_get_audit_file('https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/*.csv', default, default)
        """
    ),
    # Check for Parquet files (FOCUS format often uses parquet)
    (
        "Parquet files (*.parquet)",
        f"""
        SELECT TOP 10 * FROM 
        sys.fn_get_audit_file('https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/*.parquet', default, default)
        """
    ),
    # Check parent directory
    (
        "Files in parent directory",
        f"""
        SELECT TOP 10 * FROM 
        sys.fn_get_audit_file('https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/*.csv', default, default)
        """
    ),
    # Check with different path patterns
    (
        "Files with date pattern",
        f"""
        SELECT TOP 10 * FROM 
        sys.fn_get_audit_file('https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/*/*.csv', default, default)
        """
    )
]

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

# Try a simpler approach - create a view to explore the storage
explore_sql = f"""
-- Drop if exists
IF EXISTS (SELECT * FROM sys.views WHERE name = 'StorageExplorer')
    DROP VIEW StorageExplorer;

-- Create a view to explore storage with wildcards
CREATE VIEW StorageExplorer AS
SELECT 
    result.filepath() as FilePath,
    result.filename() as FileName
FROM OPENROWSET(
    BULK 'https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/**',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0'
) AS result;
"""

try:
    conn = pyodbc.connect(conn_str)
    cursor = conn.cursor()
    
    print("📂 Creating storage explorer view...")
    try:
        # Try to create the explorer view
        for cmd in explore_sql.split(';'):
            if cmd.strip():
                cursor.execute(cmd)
        conn.commit()
        print("✅ Storage explorer view created\n")
        
        # Query it
        print("📋 Files in storage:")
        cursor.execute("SELECT TOP 20 * FROM StorageExplorer")
        rows = cursor.fetchall()
        if rows:
            for row in rows:
                print(f"  - {row}")
        else:
            print("  No files found")
            
    except pyodbc.Error as e:
        print(f"❌ Could not create explorer view: {str(e)[:200]}\n")
    
    # Try different approaches to find files
    print("\n🔍 Attempting different file patterns...")
    print("-"*60)
    
    # Test if we can access the storage at all
    test_patterns = [
        f"https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/*.csv",
        f"https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/*.parquet",
        f"https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/*.csv",
        f"https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/**/*.csv",
        f"https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/daily/*.csv",
        f"https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/**/wiv-focus-cost*.csv"
    ]
    
    for pattern in test_patterns:
        print(f"\nTrying pattern: {pattern}")
        test_sql = f"""
        SELECT TOP 1 * FROM OPENROWSET(
            BULK '{pattern}',
            FORMAT = 'CSV',
            PARSER_VERSION = '2.0',
            HEADER_ROW = TRUE
        ) AS TestData
        """
        
        try:
            cursor.execute(test_sql)
            row = cursor.fetchone()
            if row:
                print(f"  ✅ Found data! Columns: {[desc[0] for desc in cursor.description][:5]}...")
                break
        except pyodbc.Error as e:
            error_msg = str(e)
            if "no files were found" in error_msg.lower():
                print(f"  ❌ No files match this pattern")
            elif "access" in error_msg.lower() or "permission" in error_msg.lower():
                print(f"  ❌ Permission denied - service principal needs Storage Blob Data Reader role")
            else:
                print(f"  ❌ Error: {error_msg[:100]}")
    
    cursor.close()
    conn.close()
    
except Exception as e:
    print(f"❌ Connection failed: {e}")

print("\n" + "="*60)
print("📝 Diagnosis:")
print("-"*60)
print("If no files were found:")
print("1. The billing export might not have run yet (wait 5-30 minutes)")
print("2. The export path might be different than expected")
print("3. Files might be in a different format (parquet instead of CSV)")
print("\nTo check in Azure Portal:")
print(f"1. Go to Storage Account: {STORAGE_ACCOUNT}")
print(f"2. Navigate to Container: {CONTAINER}")
print(f"3. Check the actual path and file format")
print("\nTo grant permissions:")
print(f"az role assignment create --assignee {config['client_id']} \\")
print(f"  --role 'Storage Blob Data Reader' \\")
print(f"  --scope /subscriptions/YOUR_SUB_ID/resourceGroups/rg-wiv/providers/Microsoft.Storage/storageAccounts/{STORAGE_ACCOUNT}")