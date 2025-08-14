#!/usr/bin/env python3
import pyodbc
import time
import subprocess
import json

# Configuration
config = {
    'workspace_name': 'wiv-synapse-billing',
    'tenant_id': 'ba153ff0-3397-4ef5-a214-dd33e8c37bff',
    'client_id': '554b11c1-18f9-46b5-a096-30e0a2cfae6f',
    'client_secret': 'tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams',
    'storage_account': 'billingstorage77626',
    'container': 'billing-exports'
}

print("Setting up Synapse with SAS token...")

# Generate SAS token
print("\n1. Generating SAS token...")
try:
    # Get storage key
    result = subprocess.run([
        'az', 'storage', 'account', 'keys', 'list',
        '--account-name', config['storage_account'],
        '--query', '[0].value',
        '--output', 'tsv'
    ], capture_output=True, text=True)
    
    storage_key = result.stdout.strip()
    
    # Generate SAS token
    from datetime import datetime, timedelta
    expiry = (datetime.utcnow() + timedelta(days=365)).strftime('%Y-%m-%dT%H:%MZ')
    
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
    print(f"✅ SAS token generated (valid for 1 year)")
    
except Exception as e:
    print(f"❌ Failed to generate SAS token: {e}")
    sas_token = ""

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
    
    # Drop existing objects
    print("\n2. Cleaning up existing objects...")
    try:
        cursor.execute("IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingData') DROP VIEW BillingData")
    except: pass
    
    try:
        cursor.execute("IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'BillingDataSource') DROP EXTERNAL DATA SOURCE BillingDataSource")
    except: pass
    
    try:
        cursor.execute("IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'BillingStorageCredential') DROP DATABASE SCOPED CREDENTIAL BillingStorageCredential")
    except: pass
    
    # Create SAS credential
    print("\n3. Creating SAS credential...")
    try:
        cursor.execute(f"""
            CREATE DATABASE SCOPED CREDENTIAL BillingStorageCredential
            WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
            SECRET = '{sas_token}'
        """)
        print("✅ SAS credential created")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    # Create external data source
    print("\n4. Creating external data source...")
    try:
        cursor.execute(f"""
            CREATE EXTERNAL DATA SOURCE BillingDataSource
            WITH (
                LOCATION = 'https://{config['storage_account']}.blob.core.windows.net/{config['container']}',
                CREDENTIAL = BillingStorageCredential
            )
        """)
        print("✅ External data source created")
    except Exception as e:
        print(f"❌ Error: {e}")
    
    # Create view for billing data
    print("\n5. Creating BillingData view...")
    try:
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
    print("\n6. Testing the view...")
    try:
        cursor.execute("SELECT COUNT(*) as RecordCount FROM BillingData")
        row = cursor.fetchone()
        print(f"✅ View is working! Found {row[0]} billing records")
    except Exception as e:
        print(f"⚠️ Could not query view: {e}")
    
    cursor.close()
    conn.close()
    
    print("\n✅ Database setup complete!")
    print("\nYou can now use the Python client to query the data!")
    
except Exception as e:
    print(f"❌ Connection failed: {e}")
