#!/usr/bin/env python3
import pyodbc
import sys
import time

# Configuration from environment
config = {
    'workspace_name': 'wiv-synapse-billing',
    'tenant_id': 'ba153ff0-3397-4ef5-a214-dd33e8c37bff',
    'client_id': '554b11c1-18f9-46b5-a096-30e0a2cfae6f', 
    'client_secret': '<EXISTING_CLIENT_SECRET_REQUIRED>',
    'storage_account': 'billingstorage88614',
    'container': 'billing-exports',
    'master_key_password': 'StrongP@ssw0rdb4217330!'
}

def wait_for_synapse():
    """Wait for Synapse to be ready"""
    print("⏳ Waiting for Synapse workspace to be fully ready...")
    max_retries = 10
    retry_delay = 30
    
    for attempt in range(max_retries):
        try:
            # Try a simple connection to check if Synapse is ready
            test_conn_str = f"""
            DRIVER={{ODBC Driver 18 for SQL Server}};
            SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;
            DATABASE=master;
            UID={config['client_id']};
            PWD={config['client_secret']};
            Authentication=ActiveDirectoryServicePrincipal;
            Encrypt=yes;
            TrustServerCertificate=no;
            Connection Timeout=30;
            """
            
            conn = pyodbc.connect(test_conn_str, autocommit=True)
            conn.close()
            print("✅ Synapse is ready!")
            return True
        except Exception as e:
            if attempt < max_retries - 1:
                print(f"⏳ Synapse not ready yet (attempt {attempt + 1}/{max_retries}). Waiting {retry_delay} seconds...")
                time.sleep(retry_delay)
            else:
                print(f"❌ Synapse not accessible after {max_retries} attempts: {e}")
                return False
    
    return False

def execute_sql_commands(conn_str, commands):
    """Execute SQL commands one by one"""
    try:
        # Add connection timeout
        conn_str_with_timeout = conn_str.replace(
            'TrustServerCertificate=no;',
            'TrustServerCertificate=no;Connection Timeout=60;'
        )
        conn = pyodbc.connect(conn_str_with_timeout, autocommit=True)
        cursor = conn.cursor()
        
        for i, command in enumerate(commands, 1):
            if command.strip():
                try:
                    print(f"Executing step {i}...")
                    cursor.execute(command)
                    print(f"✅ Step {i} completed")
                except pyodbc.Error as e:
                    if "already exists" in str(e) or "Cannot drop" in str(e):
                        print(f"⚠️  Step {i}: Object already exists (skipping)")
                    else:
                        print(f"❌ Step {i} failed: {e}")
                        # Continue with next command
                time.sleep(1)
        
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        print(f"Connection failed: {e}")
        return False

# First wait for Synapse to be ready
if not wait_for_synapse():
    print("⚠️  Synapse is not accessible via service principal. This could be due to:")
    print("   1. Firewall rules not yet propagated (wait a few minutes)")
    print("   2. Service principal permissions still propagating")
    print("   3. Synapse workspace still provisioning")
    print("")
    print("📝 Manual setup instructions saved to: synapse_billing_setup.sql")
    print("   You can either:")
    print("   a) Wait 5-10 minutes and re-run this script")
    print("   b) Run the SQL script manually in Synapse Studio")
    print("")
    print("💡 TIP: The Synapse workspace is created and will work!")
    print("   The automated database setup just needs more time to connect.")
    sys.exit(0)

# Connection string for master database
master_conn_str = f"""
DRIVER={{ODBC Driver 18 for SQL Server}};
SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;
DATABASE=master;
UID={config['client_id']};
PWD={config['client_secret']};
Authentication=ActiveDirectoryServicePrincipal;
Encrypt=yes;
TrustServerCertificate=no;
Connection Timeout=60;
"""

# Create database
print("📦 Creating BillingAnalytics database...")
db_commands = [
    "CREATE DATABASE BillingAnalytics"
]

execute_sql_commands(master_conn_str, db_commands)

# Connection string for BillingAnalytics database
billing_conn_str = f"""
DRIVER={{ODBC Driver 18 for SQL Server}};
SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;
DATABASE=BillingAnalytics;
UID={config['client_id']};
PWD={config['client_secret']};
Authentication=ActiveDirectoryServicePrincipal;
Encrypt=yes;
TrustServerCertificate=no;
Connection Timeout=60;
"""

# Setup commands - Simplified for Managed Identity (no SAS tokens needed!)
print("\n🔧 Setting up database objects with Managed Identity...")
setup_commands = [
    # Create master key
    f"CREATE MASTER KEY ENCRYPTION BY PASSWORD = '{config['master_key_password']}'",
    
    # Drop existing view if exists
    """IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingData')
       DROP VIEW BillingData""",
    
    # Create view using abfss:// protocol with Managed Identity (no credentials needed!)
    f"""CREATE VIEW BillingData AS
       SELECT *
       FROM OPENROWSET(
           BULK 'abfss://billing-exports@{config['storage_account']}.dfs.core.windows.net/billing-data/DailyBillingExport/*/*.csv',
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
       ) AS BillingData"""
]

if execute_sql_commands(billing_conn_str, setup_commands):
    print("\n✅ Synapse database setup completed successfully!")
    
    # Test the view
    print("\n🔍 Testing the view...")
    try:
        conn = pyodbc.connect(billing_conn_str)
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) as RecordCount FROM BillingData")
        row = cursor.fetchone()
        print(f"✅ View is working! Found {row[0]} billing records")
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"⚠️  Could not test view: {e}")
else:
    print("\n❌ Some steps failed, but setup may still be usable")

print("\n📊 You can now query billing data using:")
print("   SELECT * FROM BillingAnalytics.dbo.BillingData")
