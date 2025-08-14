#!/usr/bin/env python3
import pyodbc
import time

# Configuration
config = {
    'workspace_name': 'wiv-synapse-billing',
    'tenant_id': 'ba153ff0-3397-4ef5-a214-dd33e8c37bff',
    'client_id': '554b11c1-18f9-46b5-a096-30e0a2cfae6f',
    'client_secret': 'tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams'
}

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
Connection Timeout=30;
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
    
    cursor.close()
    conn.close()
    
except Exception as e:
    print(f"❌ Connection failed: {e}")
    print("\nPossible reasons:")
    print("1. Service principal doesn't have Synapse access")
    print("2. Firewall rules blocking access")
    print("3. Workspace not fully provisioned")
