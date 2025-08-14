import pyodbc

print("Setting up BillingAnalytics database...")

conn_str = """
DRIVER={ODBC Driver 18 for SQL Server};
SERVER=wiv-synapse-billing-ondemand.sql.azuresynapse.net;
DATABASE=master;
UID=554b11c1-18f9-46b5-a096-30e0a2cfae6f;
PWD=tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams;
Authentication=ActiveDirectoryServicePrincipal;
Encrypt=yes;
TrustServerCertificate=no;
Connection Timeout=60;
"""

try:
    # Connect to master
    print("1. Connecting to master database...")
    conn = pyodbc.connect(conn_str, autocommit=True)
    cursor = conn.cursor()
    print("✅ Connected!")
    
    # Create database
    print("2. Creating BillingAnalytics database...")
    try:
        cursor.execute("CREATE DATABASE BillingAnalytics")
        print("✅ Database created!")
    except Exception as e:
        if "already exists" in str(e) or "Database 'BillingAnalytics' already exists" in str(e):
            print("✅ Database already exists!")
        else:
            print(f"⚠️ {e}")
    
    cursor.close()
    conn.close()
    
    # Connect to BillingAnalytics
    print("3. Connecting to BillingAnalytics database...")
    billing_conn_str = conn_str.replace("DATABASE=master", "DATABASE=BillingAnalytics")
    conn = pyodbc.connect(billing_conn_str, autocommit=True)
    cursor = conn.cursor()
    print("✅ Connected to BillingAnalytics!")
    
    # Create master key
    print("4. Creating master key...")
    try:
        cursor.execute("CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd2024!'")
        print("✅ Master key created!")
    except Exception as e:
        if "already exists" in str(e):
            print("✅ Master key already exists!")
        else:
            print(f"⚠️ {e}")
    
    # Create view using abfss://
    print("5. Creating BillingData view...")
    try:
        cursor.execute("DROP VIEW IF EXISTS BillingData")
    except:
        pass
    
    cursor.execute("""
        CREATE VIEW BillingData AS
        SELECT *
        FROM OPENROWSET(
            BULK 'abfss://billing-exports@billingstorage90945.dfs.core.windows.net/billing-data/DailyBillingExport/*/*.csv',
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
    print("✅ View created!")
    
    # Test the view
    print("6. Testing the view...")
    try:
        cursor.execute("SELECT COUNT(*) as RecordCount FROM BillingData")
        row = cursor.fetchone()
        print(f"✅ SUCCESS! Found {row[0]} billing records!")
    except Exception as e:
        print(f"⚠️ View test failed: {e}")
        print("   This is normal if no billing data has been exported yet")
    
    cursor.close()
    conn.close()
    
    print("\n" + "="*60)
    print("✅ DATABASE SETUP COMPLETE!")
    print("="*60)
    print("\nYou can now:")
    print("1. Access Synapse Studio: https://web.azuresynapse.net")
    print("2. Query: SELECT * FROM BillingAnalytics.dbo.BillingData")
    print("3. Use the Python client: python3 synapse_remote_query_client.py")
    
except Exception as e:
    print(f"❌ Error: {e}")
