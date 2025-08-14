#!/usr/bin/env python3
import pyodbc
import time

# Configuration
config = {
    'workspace_name': 'wiv-synapse-billing',
    'tenant_id': 'ba153ff0-3397-4ef5-a214-dd33e8c37bff',
    'client_id': '554b11c1-18f9-46b5-a096-30e0a2cfae6f',
    'client_secret': 'tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams',
    'storage_account': 'billingstorage77626',
    'container': 'billing-exports'
}

print("Setting up Synapse database structure...")

# Connect to BillingAnalytics database
billing_conn_str = f"""
DRIVER={{ODBC Driver 18 for SQL Server}};
SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;
DATABASE=BillingAnalytics;
UID={config['client_id']};
PWD={config['client_secret']};
Authentication=ActiveDirectoryServicePrincipal;
Encrypt=yes;
TrustServerCertificate=no;
Connection Timeout=30;
"""

try:
    conn = pyodbc.connect(billing_conn_str, autocommit=True)
    cursor = conn.cursor()
    print("✅ Connected to BillingAnalytics database!")
    
    # Create master key
    print("\n1. Creating master key...")
    try:
        cursor.execute("CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd2024!'")
        print("✅ Master key created")
    except Exception as e:
        if "already exists" in str(e):
            print("⚠️ Master key already exists")
        else:
            print(f"❌ Error: {e}")
    
    # Create Managed Identity credential
    print("\n2. Creating Managed Identity credential...")
    try:
        cursor.execute("DROP DATABASE SCOPED CREDENTIAL IF EXISTS WorkspaceManagedIdentity")
        cursor.execute("CREATE DATABASE SCOPED CREDENTIAL WorkspaceManagedIdentity WITH IDENTITY = 'Managed Identity'")
        print("✅ Managed Identity credential created")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    # Create external data source
    print("\n3. Creating external data source...")
    try:
        cursor.execute("DROP EXTERNAL DATA SOURCE IF EXISTS BillingDataSource")
        cursor.execute(f"""
            CREATE EXTERNAL DATA SOURCE BillingDataSource
            WITH (
                LOCATION = 'https://{config['storage_account']}.blob.core.windows.net/{config['container']}',
                CREDENTIAL = WorkspaceManagedIdentity
            )
        """)
        print("✅ External data source created")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    # Create view for billing data
    print("\n4. Creating BillingData view...")
    try:
        # First drop if exists
        cursor.execute("DROP VIEW IF EXISTS BillingData")
        
        # Create the view
        cursor.execute("""
            CREATE VIEW BillingData AS
            SELECT *
            FROM OPENROWSET(
                BULK 'billing-data/DailyBillingExport/20250801-20250831/*.csv',
                DATA_SOURCE = 'BillingDataSource',
                FORMAT = 'CSV',
                PARSER_VERSION = '2.0',
                FIRSTROW = 2
            )
            WITH (
                date NVARCHAR(100),
                serviceFamily NVARCHAR(200),
                meterCategory NVARCHAR(200),
                meterSubCategory NVARCHAR(200),
                meterName NVARCHAR(500),
                billingAccountName NVARCHAR(200),
                costCenter NVARCHAR(100),
                resourceGroupName NVARCHAR(200),
                resourceLocation NVARCHAR(100),
                consumedService NVARCHAR(200),
                ResourceId NVARCHAR(1000),
                chargeType NVARCHAR(100),
                publisherType NVARCHAR(100),
                quantity NVARCHAR(100),
                costInBillingCurrency NVARCHAR(100),
                costInUsd NVARCHAR(100),
                PayGPrice NVARCHAR(100),
                billingCurrency NVARCHAR(10),
                subscriptionName NVARCHAR(200),
                SubscriptionId NVARCHAR(100),
                ProductName NVARCHAR(500),
                frequency NVARCHAR(100),
                unitOfMeasure NVARCHAR(100),
                tags NVARCHAR(4000)
            ) AS BillingData
        """)
        print("✅ BillingData view created")
    except Exception as e:
        print(f"❌ Error creating view: {e}")
    
    # Test the view
    print("\n5. Testing the view...")
    try:
        cursor.execute("SELECT COUNT(*) as RecordCount FROM BillingData")
        row = cursor.fetchone()
        print(f"✅ View is working! Found {row[0]} billing records")
    except Exception as e:
        print(f"⚠️ Could not query view: {e}")
        print("   This might be because:")
        print("   - No billing data has been exported yet")
        print("   - Managed Identity permissions are still propagating")
        print("   - The file path pattern needs adjustment")
    
    cursor.close()
    conn.close()
    
    print("\n✅ Database setup complete!")
    print("\nYou can now query: SELECT * FROM BillingAnalytics.dbo.BillingData")
    
except Exception as e:
    print(f"❌ Connection failed: {e}")
