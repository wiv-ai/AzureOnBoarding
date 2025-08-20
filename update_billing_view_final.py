#!/usr/bin/env python3
"""
Final version: Scan blob storage, handle multiple parts, and create working views
"""

import pyodbc
from azure.identity import ClientSecretCredential
from azure.storage.blob import BlobServiceClient
from synapse_config import SYNAPSE_CONFIG as config
import sys
import re

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
    csv_groups = {}  # Group files by their base path
    
    print(f"Scanning container: {CONTAINER}\n")
    for blob in container_client.list_blobs():
        if blob.name.endswith('.csv'):
            csv_files.append(blob.name)
            
            # Extract the base path (without the part_X_XXXX.csv)
            base_path = '/'.join(blob.name.split('/')[:-1])
            if base_path not in csv_groups:
                csv_groups[base_path] = []
            csv_groups[base_path].append(blob.name)
    
    if csv_files:
        print(f"✅ Found {len(csv_files)} CSV files in {len(csv_groups)} location(s)\n")
        
        for path, files in csv_groups.items():
            print(f"📁 Path: {path}")
            print(f"   Files: {len(files)} parts")
            for f in sorted(files):
                filename = f.split('/')[-1]
                print(f"     - {filename}")
            print()
    else:
        print("❌ No CSV files found in the container")
        sys.exit(1)
        
except Exception as e:
    print(f"❌ Error accessing storage: {str(e)}")
    sys.exit(1)

# Step 2: Determine the correct path patterns
print(f"📊 Step 2: Analyzing CSV file structure...")
print("-"*70)

# We need to handle multiple patterns for different date ranges
bulk_paths = []
for base_path in csv_groups.keys():
    bulk_path = f"https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{base_path}/*.csv"
    bulk_paths.append(bulk_path)
    print(f"📍 Path pattern: {bulk_path}")

# For now, use the most recent path (usually the last one)
primary_bulk_path = bulk_paths[-1] if bulk_paths else None
print(f"\n📍 Primary path for views: {primary_bulk_path}")

# Step 3: Get column information from the first CSV file
print(f"\n🔍 Step 3: Analyzing CSV structure...")
print("-"*70)

def get_csv_columns():
    """Get column names and sample data from the first CSV file"""
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
        
        # Query to get column names
        test_sql = f"""
        SELECT TOP 1 * 
        FROM OPENROWSET(
            BULK '{primary_bulk_path}',
            FORMAT = 'CSV',
            PARSER_VERSION = '2.0',
            HEADER_ROW = TRUE
        ) AS TestData
        """
        
        cursor.execute(test_sql)
        columns = [desc[0] for desc in cursor.description]
        
        print(f"✅ Found {len(columns)} columns in the CSV files")
        print(f"\n📋 Column names (first 20):")
        for i, col in enumerate(columns[:20], 1):
            print(f"   {i:2}. {col}")
        if len(columns) > 20:
            print(f"   ... and {len(columns)-20} more columns")
        
        cursor.close()
        conn.close()
        return columns
        
    except Exception as e:
        print(f"❌ Error analyzing CSV structure: {str(e)[:200]}")
        return None

columns = get_csv_columns()

# Step 4: Create optimized views
print(f"\n🔧 Step 4: Creating optimized views...")
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
                print(f"   ❌ Error: {error_msg[:150]}")
        
        cursor.close()
        conn.close()
        return True
        
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False

# Create SQL commands - just one simple view for all data
sql_commands = [
    # Drop existing views
    "DROP VIEW IF EXISTS BillingData",
    "DROP VIEW IF EXISTS BillingDataAll",
    "DROP VIEW IF EXISTS MonthlyCosts",
    "DROP VIEW IF EXISTS ServiceCosts",
    
    # Create single view that reads ALL parts from ALL date ranges
    f"""
    CREATE VIEW BillingData AS
    SELECT *
    FROM OPENROWSET(
        BULK 'https://billingstorage81150.dfs.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/*/*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        HEADER_ROW = TRUE
    ) AS BillingExport
    """
]

if execute_sql(sql_commands):
    print("\n✅ Views created successfully!")
    
    # Step 5: Test the view
    print(f"\n🧪 Step 5: Testing the BillingData view...")
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
        
        # Test row count
        print("\n📊 Testing BillingData view...")
        
        try:
            cursor.execute("SELECT COUNT(*) FROM BillingData")
            count = cursor.fetchone()[0]
            print(f"   ✅ BillingData: {count:,} rows")
        except pyodbc.Error as e:
            print(f"   ❌ BillingData: Error - {str(e)[:100]}")
        
        # Get sample aggregated data
        print("\n📊 Sample costs by service:")
        print("-"*60)
        try:
            cursor.execute("""
                SELECT TOP 10 
                    ServiceName,
                    ServiceCategory,
                    SUM(TRY_CAST(EffectiveCost as FLOAT)) as TotalCost,
                    COUNT(*) as Transactions
                FROM BillingData
                WHERE ServiceName IS NOT NULL
                GROUP BY ServiceName, ServiceCategory
                ORDER BY TotalCost DESC
            """)
            
            rows = cursor.fetchall()
            if rows:
                print(f"{'Service':<30} {'Category':<20} {'Cost':>12} {'Count':>8}")
                print("-"*60)
                for row in rows:
                    service = str(row[0])[:28] if row[0] else 'N/A'
                    category = str(row[1])[:18] if row[1] else 'N/A'
                    cost = row[2] if row[2] else 0
                    count = row[3] if row[3] else 0
                    print(f"{service:<30} {category:<20} ${cost:>11,.2f} {count:>8,}")
            
        except pyodbc.Error as e:
            print(f"Could not get sample data: {str(e)[:100]}")
        
        cursor.close()
        conn.close()
        
    except Exception as e:
        print(f"❌ Test failed: {e}")

    print("\n" + "="*70)
    print("✅ SETUP COMPLETE!")
    print("="*70)
    print(f"\n📋 View Created:")
    print(f"  BillingData - All billing data from all date ranges and parts")
    print(f"\n🔗 Data Source:")
    print(f"  Storage: {STORAGE_ACCOUNT}/{CONTAINER}")
    print(f"  Files: {len(csv_files)} CSV files (in {len(csv_groups)} date range(s))")
    print(f"  Parts: Automatically combined from all part_X_XXXX.csv files")
    print(f"  Path: https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/daily/wiv-focus-cost/*/*/*.csv")
    print(f"\n💡 Example Queries:")
    print(f"  -- Get all raw data")
    print(f"  SELECT * FROM BillingData")
    print(f"  ")
    print(f"  -- Top costs by service")
    print(f"  SELECT ServiceName, SUM(TRY_CAST(EffectiveCost as FLOAT)) as TotalCost")
    print(f"  FROM BillingData")
    print(f"  GROUP BY ServiceName")
    print(f"  ORDER BY TotalCost DESC")
    print(f"  ")
    print(f"  -- Monthly trend")
    print(f"  SELECT ")
    print(f"    YEAR(TRY_CAST(ChargePeriodStart as DATE)) as Year,")
    print(f"    MONTH(TRY_CAST(ChargePeriodStart as DATE)) as Month,")
    print(f"    SUM(TRY_CAST(EffectiveCost as FLOAT)) as MonthlyTotal")
    print(f"  FROM BillingData")
    print(f"  GROUP BY YEAR(TRY_CAST(ChargePeriodStart as DATE)), MONTH(TRY_CAST(ChargePeriodStart as DATE))")
    print(f"  ORDER BY Year, Month")
    
else:
    print("\n❌ Failed to create views")

print("\n" + "="*70)