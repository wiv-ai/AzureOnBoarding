#!/usr/bin/env python3
"""
Test if we can manually create the database user
"""

import pyodbc
from synapse_config import SYNAPSE_CONFIG

config = SYNAPSE_CONFIG

print("=" * 70)
print("🔧 TESTING DATABASE USER CREATION")
print("=" * 70)
print(f"Workspace: {config['workspace_name']}")
print(f"Service Principal: {config['client_id']}")
print("=" * 70)

# First, let's check if we can connect to master database
print("\n📝 Testing connection to master database...")
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
    print("Attempting to connect to master...")
    conn = pyodbc.connect(master_conn_str, autocommit=True)
    cursor = conn.cursor()
    
    # Check if we can query system tables
    cursor.execute("SELECT name FROM sys.databases")
    databases = cursor.fetchall()
    
    print("✅ Connected to master database!")
    print("Existing databases:")
    for db in databases:
        print(f"  - {db.name}")
    
    # Check if BillingAnalytics exists
    cursor.execute("SELECT name FROM sys.databases WHERE name = 'BillingAnalytics'")
    result = cursor.fetchone()
    
    if not result:
        print("\n❌ BillingAnalytics database does not exist")
        print("Attempting to create it...")
        try:
            cursor.execute("CREATE DATABASE BillingAnalytics")
            print("✅ Database created!")
        except Exception as e:
            print(f"❌ Could not create database: {e}")
    else:
        print("\n✅ BillingAnalytics database exists")
    
    cursor.close()
    conn.close()
    
except pyodbc.Error as e:
    if "Login failed" in str(e):
        print("❌ Cannot connect to master database")
        print("   The service principal doesn't have access yet")
        print("\n   This confirms the database user needs to be created manually")
    else:
        print(f"❌ Error: {e}")

# Now test BillingAnalytics database
print("\n📝 Testing connection to BillingAnalytics database...")
billing_conn_str = f"""
DRIVER={{ODBC Driver 18 for SQL Server}};
SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;
DATABASE={config['database_name']};
UID={config['client_id']};
PWD={config['client_secret']};
Authentication=ActiveDirectoryServicePrincipal;
Encrypt=yes;
TrustServerCertificate=no;
Connection Timeout=30;
"""

try:
    conn = pyodbc.connect(billing_conn_str)
    cursor = conn.cursor()
    
    print("✅ Connected to BillingAnalytics!")
    
    # Check current user
    cursor.execute("SELECT USER_NAME() as usr, SUSER_NAME() as login")
    result = cursor.fetchone()
    print(f"   Current user: {result.usr}")
    print(f"   Login: {result.login}")
    
    cursor.close()
    conn.close()
    
    print("\n✅ EVERYTHING IS WORKING!")
    
except pyodbc.Error as e:
    if "Login failed" in str(e):
        print("❌ Cannot connect to BillingAnalytics")
        print("   The database user 'wiv_account' needs to be created")
        print("\n📋 MANUAL FIX REQUIRED:")
        print("   1. Open Synapse Studio: https://web.azuresynapse.net")
        print(f"   2. Select workspace: {config['workspace_name']}")
        print("   3. Run this SQL:")
        print("-" * 70)
        print("""
CREATE DATABASE BillingAnalytics;
GO

USE BillingAnalytics;
GO

CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd2024!';
GO

CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
GO

ALTER ROLE db_datareader ADD MEMBER [wiv_account];
ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
GO
""")
        print("-" * 70)
    elif "Database 'BillingAnalytics' does not exist" in str(e):
        print("❌ BillingAnalytics database doesn't exist")
        print("   Need to create it first in Synapse Studio")
    else:
        print(f"❌ Error: {e}")