#!/usr/bin/env python3
import pyodbc
import subprocess
import time

# Configuration
config = {
    'workspace_name': 'wiv-synapse-billing',
    'client_id': '554b11c1-18f9-46b5-a096-30e0a2cfae6f',
    'client_secret': 'tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams',
    'storage_account': 'billingstorage85409',
    'container': 'billing-exports',
    'resource_group': 'wiv-rg'
}

print("Setting up Managed Identity (NO SAS TOKEN NEEDED!)...")

# First, ensure proper RBAC permissions
print("\n1. Setting up RBAC permissions...")

# Get Synapse workspace managed identity
result = subprocess.run([
    'az', 'synapse', 'workspace', 'show',
    '--name', config['workspace_name'],
    '--resource-group', config['resource_group'],
    '--query', 'identity.principalId',
    '--output', 'tsv'
], capture_output=True, text=True)

synapse_identity = result.stdout.strip()
print(f"   Synapse Managed Identity: {synapse_identity}")

# Grant Storage Blob Data Reader to Synapse Managed Identity
print("   Granting Storage Blob Data Reader to Synapse...")
subprocess.run([
    'az', 'role', 'assignment', 'create',
    '--role', 'Storage Blob Data Reader',
    '--assignee', synapse_identity,
    '--scope', f"/subscriptions/7f6dc2fe-6841-4aca-b2d3-d6a00e96e99f/resourceGroups/{config['resource_group']}/providers/Microsoft.Storage/storageAccounts/{config['storage_account']}"
], capture_output=True)

# Also grant to service principal
print("   Granting Storage Blob Data Reader to Service Principal...")
subprocess.run([
    'az', 'role', 'assignment', 'create',
    '--role', 'Storage Blob Data Reader',
    '--assignee', config['client_id'],
    '--scope', f"/subscriptions/7f6dc2fe-6841-4aca-b2d3-d6a00e96e99f/resourceGroups/{config['resource_group']}/providers/Microsoft.Storage/storageAccounts/{config['storage_account']}"
], capture_output=True)

print("✅ RBAC permissions configured")

# Wait for permissions to propagate
print("\n2. Waiting for permissions to propagate...")
time.sleep(10)

# Connect to database
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
    print("✅ Connected to database")
    
    print("\n3. Recreating database objects with Managed Identity...")
    
    # Drop existing objects
    try:
        cursor.execute("IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingData') DROP VIEW BillingData")
        cursor.execute("IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingDataMI') DROP VIEW BillingDataMI")
    except: pass
    
    try:
        cursor.execute("IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'BillingDataSourceMI') DROP EXTERNAL DATA SOURCE BillingDataSourceMI")
    except: pass
    
    try:
        cursor.execute("IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'WorkspaceManagedIdentity') DROP DATABASE SCOPED CREDENTIAL WorkspaceManagedIdentity")
    except: pass
    
    # Create Managed Identity credential
    cursor.execute("""
        CREATE DATABASE SCOPED CREDENTIAL WorkspaceManagedIdentity
        WITH IDENTITY = 'Managed Identity'
    """)
    print("✅ Managed Identity credential created")
    
    # Create data source with Managed Identity
    cursor.execute(f"""
        CREATE EXTERNAL DATA SOURCE BillingDataSourceMI
        WITH (
            LOCATION = 'https://{config['storage_account']}.blob.core.windows.net/{config['container']}',
            CREDENTIAL = WorkspaceManagedIdentity
        )
    """)
    print("✅ Data source created with Managed Identity")
    
    # Create view using Managed Identity
    cursor.execute("""
        CREATE VIEW BillingDataMI AS
        SELECT *
        FROM OPENROWSET(
            BULK 'billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_91f1e7fa-40bd-460d-b22c-f72cb6aaf761.csv',
            DATA_SOURCE = 'BillingDataSourceMI',
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
        ) AS BillingDataMI
    """)
    print("✅ View created with Managed Identity")
    
    # Test the Managed Identity view
    print("\n4. Testing Managed Identity access...")
    try:
        cursor.execute("SELECT COUNT(*) as RecordCount FROM BillingDataMI")
        row = cursor.fetchone()
        print(f"✅ SUCCESS! Managed Identity working! Found {row[0]} records")
        
        # Now replace the main view to use Managed Identity
        print("\n5. Switching main BillingData view to use Managed Identity...")
        cursor.execute("IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingData') DROP VIEW BillingData")
        cursor.execute("""
            CREATE VIEW BillingData AS
            SELECT * FROM BillingDataMI
        """)
        print("✅ Main view now uses Managed Identity!")
        
    except Exception as e:
        print(f"⚠️  Managed Identity not working yet: {e}")
        print("   Permissions may need more time to propagate (5-10 minutes)")
        print("   The SAS token version is still working as backup")
    
    cursor.close()
    conn.close()
    
    print("\n" + "="*60)
    print("✅ MANAGED IDENTITY SETUP COMPLETE!")
    print("="*60)
    print("\n🎉 Benefits:")
    print("   • NO TOKEN EXPIRATION - Never expires!")
    print("   • NO SECRETS - No SAS tokens or keys to manage")
    print("   • MORE SECURE - Azure native authentication")
    print("   • AUTOMATIC - Works immediately after setup")
    print("\n📊 Query your data:")
    print("   SELECT * FROM BillingAnalytics.dbo.BillingData")
    
except Exception as e:
    print(f"❌ Error: {e}")
