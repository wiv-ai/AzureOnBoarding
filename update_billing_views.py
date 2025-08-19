#!/usr/bin/env python3
"""
Update billing views with the correct path pattern including date subdirectories
"""

import pyodbc
from synapse_config import SYNAPSE_CONFIG as config

# Your storage configuration with corrected path
STORAGE_ACCOUNT = "wivcostexports"
CONTAINER = "costexport"
EXPORT_PATH = "daily/wiv-focus-cost"

def execute_sql_commands(sql_commands):
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
        print(f"🔌 Connecting to Synapse workspace: {config['workspace_name']}")
        conn = pyodbc.connect(conn_str)
        cursor = conn.cursor()
        print("✅ Connected successfully\n")
        
        for sql_command in sql_commands:
            if not sql_command.strip():
                continue
                
            cmd_preview = sql_command.strip()[:150].replace('\n', ' ')
            print(f"📝 Executing: {cmd_preview}...")
            
            try:
                cursor.execute(sql_command)
                conn.commit()
                print("   ✅ Success\n")
            except pyodbc.Error as e:
                error_msg = str(e)
                if "already exists" in error_msg.lower():
                    print(f"   ⚠️  Already exists (skipping)\n")
                else:
                    print(f"   ❌ Error: {error_msg[:200]}\n")
        
        cursor.close()
        conn.close()
        return True
        
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False

print("="*60)
print("🚀 Updating Billing Views with Correct Path Pattern")
print("="*60)
print(f"Storage Account: {STORAGE_ACCOUNT}")
print(f"Container: {CONTAINER}")
print(f"Export Path: {EXPORT_PATH}")
print(f"Pattern: https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/*/*.csv")
print("="*60 + "\n")

# SQL commands to update the billing views with correct path
sql_commands = [
    # Drop existing views
    """
    IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingData')
        DROP VIEW BillingData
    """,
    
    """
    IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingDataFOCUS')
        DROP VIEW BillingDataFOCUS
    """,
    
    """
    IF EXISTS (SELECT * FROM sys.views WHERE name = 'DailyCosts')
        DROP VIEW DailyCosts
    """,
    
    # Create main BillingData view with corrected path (includes date subdirectory)
    f"""
    CREATE VIEW BillingData AS
    SELECT *
    FROM OPENROWSET(
        BULK 'https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/*/*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        HEADER_ROW = TRUE
    ) AS BillingExport
    """,
    
    # Create FOCUS format view with corrected path
    f"""
    CREATE VIEW BillingDataFOCUS AS
    SELECT *
    FROM OPENROWSET(
        BULK 'https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/*/*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        HEADER_ROW = TRUE
    ) AS FOCUSData
    """,
    
    # Create a monitoring view to check for data availability
    f"""
    CREATE VIEW BillingDataStatus AS
    SELECT 
        'https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/*/*.csv' as ExpectedPath,
        GETDATE() as CheckedAt,
        CASE 
            WHEN EXISTS (
                SELECT TOP 1 * FROM OPENROWSET(
                    BULK 'https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/*/*.csv',
                    FORMAT = 'CSV',
                    PARSER_VERSION = '2.0',
                    HEADER_ROW = TRUE
                ) AS TestData
            ) THEN 'Data Available'
            ELSE 'No Data Yet'
        END as Status
    """
]

# Execute the SQL commands
if execute_sql_commands(sql_commands):
    print("\n" + "="*60)
    print("✅ Views updated with correct path pattern!")
    print("="*60)
    
    # Test if we can now access the data
    print("\n🔍 Testing data access with new path pattern...")
    
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
        
        # First check if files exist
        print("\n📊 Checking if billing data files exist...")
        test_sql = f"""
        SELECT TOP 1 * FROM OPENROWSET(
            BULK 'https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/*/*.csv',
            FORMAT = 'CSV',
            PARSER_VERSION = '2.0',
            HEADER_ROW = TRUE
        ) AS TestData
        """
        
        try:
            cursor.execute(test_sql)
            row = cursor.fetchone()
            
            if row:
                print("✅ Data found! Files exist at the specified path.")
                
                # Get column names
                columns = [desc[0] for desc in cursor.description]
                print(f"\n📋 Available columns ({len(columns)} total):")
                for i, col in enumerate(columns[:10]):  # Show first 10 columns
                    print(f"   {i+1}. {col}")
                if len(columns) > 10:
                    print(f"   ... and {len(columns)-10} more columns")
                
                # Try to get a sample of data
                print("\n📊 Sample data from BillingData view:")
                sample_sql = "SELECT TOP 5 * FROM BillingData"
                cursor.execute(sample_sql)
                sample_rows = cursor.fetchmany(5)
                
                if sample_rows:
                    # Show first few columns of sample data
                    print("-" * 60)
                    for row in sample_rows:
                        print(f"   {str(row[:3])[:100]}...")  # Show first 3 columns
                        
        except pyodbc.Error as e:
            error_msg = str(e)
            if "no files were found" in error_msg.lower():
                print("❌ No files found at the specified path.")
                print(f"\n📝 Path being checked:")
                print(f"   https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/*/*.csv")
                print("\nPossible issues:")
                print("1. Billing export hasn't run yet (wait 5-30 minutes)")
                print("2. Files might be in a different format (.parquet instead of .csv)")
                print("3. Path structure might be different")
                print("\nTo verify in Azure Storage Explorer or Portal:")
                print(f"   Storage Account: {STORAGE_ACCOUNT}")
                print(f"   Container: {CONTAINER}")
                print(f"   Expected path: {EXPORT_PATH}/YYYYMMDD-YYYYMMDD/*.csv")
            elif "permission" in error_msg.lower() or "access" in error_msg.lower():
                print("❌ Permission denied accessing storage.")
                print("\nGrant Storage Blob Data Reader role:")
                print(f"az role assignment create --assignee {config['client_id']} \\")
                print(f"  --role 'Storage Blob Data Reader' \\")
                print(f"  --scope /subscriptions/2803f753-2892-45ac-b573-5c6ee0072efb/resourceGroups/rg-wiv/providers/Microsoft.Storage/storageAccounts/{STORAGE_ACCOUNT}")
            else:
                print(f"❌ Error: {error_msg[:200]}")
        
        cursor.close()
        conn.close()
        
    except Exception as e:
        print(f"Test failed: {e}")
    
    print("\n" + "="*60)
    print("📋 Views Created/Updated:")
    print("  - BillingData: Raw billing data (all columns)")
    print("  - BillingDataFOCUS: FOCUS format billing data")
    print("  - BillingDataStatus: Check if data is available")
    print("\n🔗 Storage Path Pattern:")
    print(f"  https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/*/*.csv")
    print("  (The /* represents date-based subdirectories like 20250801-20250831)")
    
else:
    print("\n❌ Failed to update views. Check the errors above.")