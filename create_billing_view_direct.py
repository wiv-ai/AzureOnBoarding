#!/usr/bin/env python3
"""
Create BillingData view directly in Synapse
"""

import pyodbc
from synapse_config import SYNAPSE_CONFIG, STORAGE_CONFIG

def create_billing_view():
    """Create the BillingData view in Synapse"""
    
    config = SYNAPSE_CONFIG
    storage = STORAGE_CONFIG
    
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
    print("📊 CREATING BILLING DATA VIEW IN SYNAPSE")
    print("=" * 70)
    print(f"Workspace: {config['workspace_name']}")
    print(f"Database: {config['database_name']}")
    print(f"Storage: {storage['storage_account']}/{storage['container']}")
    print("=" * 70)
    print()
    
    try:
        print("Connecting to Synapse...")
        conn = pyodbc.connect(conn_str, autocommit=True)
        cursor = conn.cursor()
        
        # Drop existing view if exists
        print("Dropping existing view if exists...")
        cursor.execute("IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingData') DROP VIEW BillingData")
        
        # Create the view with the known path pattern
        print("Creating BillingData view...")
        create_view_sql = f"""
        CREATE VIEW BillingData AS
        SELECT *
        FROM OPENROWSET(
            BULK 'https://{storage['storage_account']}.blob.core.windows.net/{storage['container']}/daily/wiv-focus-cost/*/*/*.csv',
            FORMAT = 'CSV',
            PARSER_VERSION = '2.0',
            HEADER_ROW = TRUE
        ) AS BillingExport
        """
        
        cursor.execute(create_view_sql)
        print("✅ BillingData view created successfully!")
        
        # Test the view
        print("\nTesting the view...")
        cursor.execute("SELECT COUNT(*) as row_count FROM BillingData")
        result = cursor.fetchone()
        print(f"✅ View is working! Found {result.row_count} rows")
        
        # Get column names
        cursor.execute("SELECT TOP 1 * FROM BillingData")
        columns = [column[0] for column in cursor.description]
        print(f"\n📋 Available columns ({len(columns)}):")
        for i in range(0, len(columns), 4):
            cols = columns[i:i+4]
            print("   " + ", ".join(cols))
        
        cursor.close()
        conn.close()
        
        print("\n✅ SUCCESS! You can now run test_billing_queries.py")
        return True
        
    except pyodbc.Error as e:
        print(f"\n❌ Error: {e}")
        
        if "Cannot find the CREDENTIAL" in str(e):
            print("\n📝 The view needs credentials. Run this SQL in Synapse Studio:")
            print("-" * 70)
            print(f"""
-- Create master key if not exists
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd2024!';
GO

-- Create database scoped credential
CREATE DATABASE SCOPED CREDENTIAL BillingStorageCredential
WITH IDENTITY = 'Managed Identity';
GO

-- Create external data source
CREATE EXTERNAL DATA SOURCE BillingStorage
WITH (
    TYPE = BLOB_STORAGE,
    LOCATION = 'https://{storage['storage_account']}.blob.core.windows.net/{storage['container']}',
    CREDENTIAL = BillingStorageCredential
);
GO

-- Then create the view
CREATE VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK 'https://{storage['storage_account']}.blob.core.windows.net/{storage['container']}/daily/wiv-focus-cost/*/*/*.csv',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
) AS BillingExport;
GO
""")
            print("-" * 70)
        
        return False

if __name__ == "__main__":
    create_billing_view()