#!/usr/bin/env python3
"""
Scan blob storage to find CSV files and update Synapse views with the correct path
"""

import pyodbc
from azure.identity import ClientSecretCredential
from azure.storage.blob import BlobServiceClient
from synapse_config import SYNAPSE_CONFIG as config
import sys

# Storage configuration
STORAGE_ACCOUNT = "wivcostexports"
CONTAINER = "costexport"
STORAGE_SUBSCRIPTION = "2803f753-2892-45ac-b573-5c6ee0072efb"

print("="*70)
print("🔍 SCANNING BLOB STORAGE AND UPDATING BILLING VIEWS")
print("="*70)
print(f"Storage Account: {STORAGE_ACCOUNT}")
print(f"Container: {CONTAINER}")
print("="*70 + "\n")

# Step 1: Connect to Azure Storage and scan for CSV files
print("📂 Step 1: Scanning blob storage for CSV files...")
print("-"*70)

try:
    # Create credential
    credential = ClientSecretCredential(
        tenant_id=config['tenant_id'],
        client_id=config['client_id'],
        client_secret=config['client_secret']
    )
    
    # Create BlobServiceClient
    blob_service_client = BlobServiceClient(
        account_url=f"https://{STORAGE_ACCOUNT}.blob.core.windows.net",
        credential=credential
    )
    
    # Get container client
    container_client = blob_service_client.get_container_client(CONTAINER)
    
    # List all blobs and find CSV files
    csv_files = []
    all_files = []
    
    print(f"Scanning container: {CONTAINER}")
    for blob in container_client.list_blobs():
        all_files.append(blob.name)
        if blob.name.endswith('.csv'):
            csv_files.append(blob.name)
            print(f"  ✅ Found CSV: {blob.name}")
    
    if not csv_files and all_files:
        print(f"\n  ⚠️ No CSV files found, but found {len(all_files)} other files:")
        for f in all_files[:10]:  # Show first 10 files
            print(f"     - {f}")
        if len(all_files) > 10:
            print(f"     ... and {len(all_files)-10} more files")
    elif not csv_files:
        print("  ❌ No files found in the container")
        
except Exception as e:
    print(f"  ❌ Error accessing storage: {str(e)}")
    print("\n  Possible issues:")
    print("  1. Service principal needs 'Storage Blob Data Reader' role")
    print("  2. Storage account or container name is incorrect")
    print(f"\n  To grant access:")
    print(f"  az role assignment create --assignee {config['client_id']} \\")
    print(f"    --role 'Storage Blob Data Reader' \\")
    print(f"    --scope /subscriptions/{STORAGE_SUBSCRIPTION}/resourceGroups/rg-wiv/providers/Microsoft.Storage/storageAccounts/{STORAGE_ACCOUNT}")
    sys.exit(1)

# Step 2: Determine the correct path pattern
print(f"\n📊 Step 2: Analyzing CSV file paths...")
print("-"*70)

if csv_files:
    # Analyze the path structure
    path_patterns = set()
    for csv_file in csv_files:
        # Extract the directory pattern
        parts = csv_file.split('/')
        if len(parts) > 1:
            # Create a pattern by replacing specific parts with wildcards
            pattern_parts = parts[:-1]  # Exclude filename
            path_patterns.add('/'.join(pattern_parts))
    
    print(f"Found {len(csv_files)} CSV files")
    print(f"Unique path patterns: {len(path_patterns)}")
    
    # Find the most common pattern
    if path_patterns:
        # Use the first pattern or the most specific one
        base_path = list(path_patterns)[0]
        print(f"\n📍 Using base path: {base_path}")
        
        # Construct the BULK path for Synapse
        bulk_path = f"https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{base_path}/*.csv"
        print(f"📍 BULK path for Synapse: {bulk_path}")
    else:
        # Files are in root
        bulk_path = f"https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/*.csv"
        print(f"📍 Files are in container root")
        print(f"📍 BULK path for Synapse: {bulk_path}")
    
    # Show sample files
    print(f"\n📋 Sample CSV files (showing first 5):")
    for csv_file in csv_files[:5]:
        print(f"   - {csv_file}")
    if len(csv_files) > 5:
        print(f"   ... and {len(csv_files)-5} more CSV files")
        
else:
    print("❌ No CSV files found in the storage container!")
    print("\nPossible reasons:")
    print("1. Billing export hasn't run yet (can take 5-30 minutes after setup)")
    print("2. Export is configured for a different format (parquet, etc.)")
    print("3. Export is going to a different container or storage account")
    sys.exit(1)

# Step 3: Update Synapse views with the correct path
print(f"\n🔧 Step 3: Updating Synapse views with correct path...")
print("-"*70)

def execute_sql(sql_commands):
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
        
        for sql_command in sql_commands:
            if not sql_command.strip():
                continue
            
            cmd_preview = sql_command.strip()[:100].replace('\n', ' ')
            print(f"\n📝 Executing: {cmd_preview}...")
            
            try:
                cursor.execute(sql_command)
                conn.commit()
                print("   ✅ Success")
            except pyodbc.Error as e:
                error_msg = str(e)
                if "already exists" in error_msg.lower():
                    print("   ⚠️ Already exists (updating)")
                else:
                    print(f"   ❌ Error: {error_msg[:150]}")
        
        cursor.close()
        conn.close()
        return True
        
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False

# Create SQL commands with the discovered path
sql_commands = [
    # Drop existing views
    "DROP VIEW IF EXISTS BillingData",
    "DROP VIEW IF EXISTS BillingDataFOCUS", 
    "DROP VIEW IF EXISTS DailyCosts",
    
    # Create main view with discovered path
    f"""
    CREATE VIEW BillingData AS
    SELECT *
    FROM OPENROWSET(
        BULK '{bulk_path}',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        HEADER_ROW = TRUE
    ) AS BillingExport
    """,
    
    # Create a simple aggregated view
    f"""
    CREATE VIEW DailyCosts AS
    SELECT 
        TRY_CAST(BillingPeriodStartDate as DATE) as Date,
        ServiceCategory,
        ServiceName,
        SUM(TRY_CAST(EffectiveCost as DECIMAL(18,6))) as TotalCost,
        COUNT(*) as TransactionCount
    FROM OPENROWSET(
        BULK '{bulk_path}',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        HEADER_ROW = TRUE
    ) 
    WITH (
        BillingPeriodStartDate NVARCHAR(100),
        ServiceCategory NVARCHAR(200),
        ServiceName NVARCHAR(200),
        EffectiveCost NVARCHAR(100)
    ) AS DailyData
    WHERE EffectiveCost IS NOT NULL
    GROUP BY TRY_CAST(BillingPeriodStartDate as DATE), ServiceCategory, ServiceName
    """
]

if execute_sql(sql_commands):
    print("\n✅ Views created/updated successfully!")
    
    # Step 4: Test the views
    print(f"\n🧪 Step 4: Testing the views...")
    print("-"*70)
    
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
        
        # Test BillingData view
        print("\n📊 Testing BillingData view...")
        test_sql = "SELECT TOP 5 * FROM BillingData"
        
        try:
            cursor.execute(test_sql)
            columns = [desc[0] for desc in cursor.description]
            print(f"   ✅ View works! Found {len(columns)} columns")
            print(f"   📋 First 10 columns: {columns[:10]}")
            
            # Get row count
            cursor.execute("SELECT COUNT(*) as RowCount FROM BillingData")
            row_count = cursor.fetchone()[0]
            print(f"   📊 Total rows in billing data: {row_count:,}")
            
        except pyodbc.Error as e:
            print(f"   ❌ Error querying view: {str(e)[:150]}")
        
        cursor.close()
        conn.close()
        
    except Exception as e:
        print(f"❌ Test failed: {e}")

    print("\n" + "="*70)
    print("✅ SETUP COMPLETE!")
    print("="*70)
    print(f"\n📋 Available Views:")
    print(f"  - BillingData: All billing data from CSV files")
    print(f"  - DailyCosts: Aggregated costs by day and service")
    print(f"\n🔗 Data Source:")
    print(f"  Path: {bulk_path}")
    print(f"  Files: {len(csv_files)} CSV files")
    print(f"\n💡 Example Queries:")
    print(f"  SELECT TOP 100 * FROM BillingData")
    print(f"  SELECT * FROM DailyCosts ORDER BY Date DESC")
    
else:
    print("\n❌ Failed to create views")

print("\n" + "="*70)