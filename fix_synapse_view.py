#!/usr/bin/env python3
import pyodbc
import subprocess
from datetime import datetime, timedelta

# Configuration
config = {
    'workspace_name': 'wiv-synapse-billing',
    'client_id': '554b11c1-18f9-46b5-a096-30e0a2cfae6f',
    'client_secret': 'tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams',
    'storage_account': 'billingstorage85409',
    'container': 'billing-exports'
}

print("Fixing Synapse view with correct storage account...")

# Generate new SAS token for correct storage account
print("\n1. Generating SAS token for billingstorage85409...")
try:
    result = subprocess.run([
        'az', 'storage', 'account', 'keys', 'list',
        '--account-name', config['storage_account'],
        '--query', '[0].value',
        '--output', 'tsv'
    ], capture_output=True, text=True)
    
    storage_key = result.stdout.strip()
    
    expiry = (datetime.now() + timedelta(days=365)).strftime('%Y-%m-%dT%H:%MZ')
    
    result = subprocess.run([
        'az', 'storage', 'container', 'generate-sas',
        '--account-name', config['storage_account'],
        '--name', config['container'],
        '--permissions', 'rl',
        '--expiry', expiry,
        '--account-key', storage_key,
        '--output', 'tsv'
    ], capture_output=True, text=True)
    
    sas_token = result.stdout.strip()
    print(f"✅ SAS token generated")
    
except Exception as e:
    print(f"❌ Failed to generate SAS token: {e}")
    exit(1)

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
    
    # Drop existing objects
    print("\n2. Recreating database objects...")
    
    # Drop view
    try:
        cursor.execute("IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingData') DROP VIEW BillingData")
    except: pass
    
    # Drop data source
    try:
        cursor.execute("IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'BillingDataSource') DROP EXTERNAL DATA SOURCE BillingDataSource")
    except: pass
    
    # Drop credential
    try:
        cursor.execute("IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'BillingStorageCredential') DROP DATABASE SCOPED CREDENTIAL BillingStorageCredential")
    except: pass
    
    # Create new credential
    cursor.execute(f"""
        CREATE DATABASE SCOPED CREDENTIAL BillingStorageCredential
        WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
        SECRET = '{sas_token}'
    """)
    print("✅ Credential created")
    
    # Create data source with correct storage account
    cursor.execute(f"""
        CREATE EXTERNAL DATA SOURCE BillingDataSource
        WITH (
            LOCATION = 'https://{config['storage_account']}.blob.core.windows.net/{config['container']}',
            CREDENTIAL = BillingStorageCredential
        )
    """)
    print("✅ Data source created")
    
    # Create view with exact path
    cursor.execute("""
        CREATE VIEW BillingData AS
        SELECT *
        FROM OPENROWSET(
            BULK 'billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_91f1e7fa-40bd-460d-b22c-f72cb6aaf761.csv',
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
    print("✅ View created with exact file path")
    
    # Test the view
    print("\n3. Testing the view...")
    cursor.execute("SELECT COUNT(*) as RecordCount FROM BillingData")
    row = cursor.fetchone()
    print(f"✅ SUCCESS! Found {row[0]} billing records")
    
    # Show sample data
    print("\n4. Sample data:")
    cursor.execute("SELECT TOP 3 date, serviceFamily, resourceGroupName, costInUsd FROM BillingData WHERE costInUsd IS NOT NULL AND costInUsd != '0'")
    for row in cursor.fetchall():
        print(f"   {row[0]} | {row[1]} | {row[2]} | ${row[3]}")
    
    cursor.close()
    conn.close()
    
    print("\n✅ COMPLETE! Database is fully configured and working!")
    
except Exception as e:
    print(f"❌ Error: {e}")
