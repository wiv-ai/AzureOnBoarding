#!/usr/bin/env python3
"""
Create BillingData view with the correct storage path
"""

import pyodbc
from synapse_config import SYNAPSE_CONFIG

def create_billing_view():
    config = SYNAPSE_CONFIG
    
    # Connection string
    conn_str = f"""
    DRIVER={{ODBC Driver 18 for SQL Server}};
    SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;
    DATABASE={config['database_name']};
    UID={config['client_id']};
    PWD={config['client_secret']};
    Authentication=ActiveDirectoryServicePrincipal;
    Encrypt=yes;
    TrustServerCertificate=no;
    Connection Timeout=60;
    """
    
    print("=" * 70)
    print("📊 CREATING BILLING DATA VIEW WITH CORRECT PATH")
    print("=" * 70)
    
    # The correct storage path from your screenshot
    storage_account = "wivcostexports"  # Assuming this based on previous config
    container = "billing-exports"
    path = "billing-data/DailyBillingExport"
    
    print(f"Storage Account: {storage_account}")
    print(f"Container: {container}")
    print(f"Path: {path}")
    print("=" * 70)
    
    try:
        print("\nConnecting to Synapse...")
        conn = pyodbc.connect(conn_str, autocommit=True)
        cursor = conn.cursor()
        print("✅ Connected")
        
        # Drop existing view if exists
        print("Dropping existing view if exists...")
        cursor.execute("IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingData') DROP VIEW BillingData")
        
        # Create the view with the correct path
        # Using wildcard for dates to get all exports
        create_view_sql = f"""
        CREATE VIEW BillingData AS
        SELECT *
        FROM OPENROWSET(
            BULK 'https://{storage_account}.blob.core.windows.net/{container}/{path}/*/*.csv',
            FORMAT = 'CSV',
            PARSER_VERSION = '2.0',
            HEADER_ROW = TRUE
        ) AS BillingExport
        """
        
        print("Creating BillingData view...")
        print(f"Path pattern: https://{storage_account}.blob.core.windows.net/{container}/{path}/*/*.csv")
        
        cursor.execute(create_view_sql)
        print("✅ BillingData view created successfully!")
        
        # Test the view
        print("\nTesting the view...")
        cursor.execute("SELECT COUNT(*) as row_count FROM BillingData")
        result = cursor.fetchone()
        print(f"✅ View is working! Found {result.row_count} rows")
        
        # Get sample data
        cursor.execute("SELECT TOP 5 * FROM BillingData")
        rows = cursor.fetchall()
        if rows:
            # Get column names
            columns = [column[0] for column in cursor.description]
            print(f"\n📋 Columns ({len(columns)}):")
            for i in range(0, len(columns), 4):
                cols = columns[i:i+4]
                print("   " + ", ".join(cols))
        
        cursor.close()
        conn.close()
        
        print("\n✅ SUCCESS! The BillingData view is ready.")
        print("You can now run test_billing_queries.py")
        return True
        
    except pyodbc.Error as e:
        print(f"\n❌ Error: {e}")
        
        if "Content of directory on path" in str(e):
            print("\n⚠️ The storage path cannot be accessed. Possible issues:")
            print("1. The storage account name might be different")
            print("2. Synapse needs permission to access the storage")
            print("3. The path pattern might need adjustment")
            print("\nTry this SQL in Synapse Studio to test different paths:")
            print("-" * 70)
            print(f"""
-- Test with specific date range (from your screenshot)
CREATE VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK 'https://{storage_account}.blob.core.windows.net/{container}/{path}/20250801-20250831/*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport;
GO

-- Or if the storage account is different, update it:
-- BULK 'https://YOUR_STORAGE_ACCOUNT.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/*/*.csv'
""")
            print("-" * 70)
        
        return False

if __name__ == "__main__":
    create_billing_view()