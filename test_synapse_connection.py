#!/usr/bin/env python3
"""
Synapse Connection Test Tool
Tests the connection to Azure Synapse and verifies the database setup
"""
import pyodbc
import time
import sys

# Import configuration from synapse_config.py if it exists
try:
    from synapse_config import SYNAPSE_CONFIG
    config = {
        'workspace_name': SYNAPSE_CONFIG['workspace_name'],
        'tenant_id': SYNAPSE_CONFIG['tenant_id'],
        'client_id': SYNAPSE_CONFIG['client_id'],
        'client_secret': SYNAPSE_CONFIG['client_secret']
    }
    print("✅ Using configuration from synapse_config.py")
except ImportError:
    # Fallback configuration
    config = {
        'workspace_name': 'wiv-synapse-billing',
        'tenant_id': 'ba153ff0-3397-4ef5-a214-dd33e8c37bff',
        'client_id': '554b11c1-18f9-46b5-a096-30e0a2cfae6f',
        'client_secret': 'tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams'
    }
    print("⚠️  Using fallback configuration (synapse_config.py not found)")

print("Testing Synapse connection...")
print(f"Workspace: {config['workspace_name']}")
print(f"Client ID: {config['client_id']}")

# Try connecting to master database first
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

try:
    print("\n1. Connecting to master database...")
    conn = pyodbc.connect(master_conn_str, autocommit=True)
    cursor = conn.cursor()
    print("✅ Connected to master database!")
    
    # Check if BillingAnalytics database exists
    print("\n2. Checking for BillingAnalytics database...")
    cursor.execute("SELECT name FROM sys.databases WHERE name = 'BillingAnalytics'")
    result = cursor.fetchone()
    
    if result:
        print("✅ BillingAnalytics database exists!")
    else:
        print("⚠️ BillingAnalytics database does not exist. Creating it...")
        try:
            cursor.execute("CREATE DATABASE BillingAnalytics")
            print("✅ Database created successfully!")
        except Exception as e:
            print(f"❌ Failed to create database: {e}")
    
    # Test BillingData view if database exists
    if result:
        print("\n3. Testing BillingData view...")
        try:
            cursor.execute("SELECT COUNT(*) as RecordCount FROM BillingAnalytics.dbo.BillingData")
            row = cursor.fetchone()
            print(f"✅ BillingData view is working! Found {row[0]} records")
            
            # Show sample data
            print("\n4. Sample billing data:")
            cursor.execute("""
                SELECT TOP 3 
                    CAST(date AS DATE) as Date,
                    serviceFamily,
                    resourceGroupName,
                    CAST(costInUsd AS DECIMAL(10,6)) as CostUSD
                FROM BillingAnalytics.dbo.BillingData 
                WHERE costInUsd IS NOT NULL AND costInUsd != '0'
                ORDER BY date DESC
            """)
            for row in cursor.fetchall():
                print(f"   {row[0]} | {row[1]} | {row[2]} | ${row[3]:.6f}")
                
        except Exception as e:
            print(f"⚠️  BillingData view not accessible: {str(e)[:100]}")
            print("   The view may need to be created or permissions may need time to propagate")
    
    cursor.close()
    conn.close()
    
    print("\n" + "="*60)
    print("✅ SYNAPSE CONNECTION TEST COMPLETE")
    print("="*60)
    
except Exception as e:
    print(f"❌ Connection failed: {e}")
    print("\nPossible reasons:")
    print("1. Service principal doesn't have Synapse access")
    print("2. Firewall rules blocking access")
    print("3. Workspace not fully provisioned")
    print("4. Incorrect credentials in synapse_config.py")
    sys.exit(1)
