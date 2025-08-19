#!/usr/bin/env python3
"""
Test Synapse authentication with provided credentials
"""

import pyodbc
from azure.identity import ClientSecretCredential
import sys

# Configuration from user
config = {
    'tenant_id': 'ba153ff0-3397-4ef5-a214-dd33e8c37bff',
    'client_id': '554b11c1-18f9-46b5-a096-30e0a2cfae6f',
    'client_secret': 'jg68Q~GC6KhpFU7S35ZP1KNkB-hXmDQ15sq5FcUf',
    'workspace_name': 'wiv-synapse-billing',
    'database_name': 'BillingAnalytics'  # Assuming same database
}

print("="*70)
print("🔍 TESTING SYNAPSE AUTHENTICATION")
print("="*70)
print(f"Workspace: {config['workspace_name']}")
print(f"Database: {config['database_name']}")
print(f"Client ID: {config['client_id']}")
print(f"Tenant ID: {config['tenant_id']}")
print("="*70)

# Test 1: Verify Azure AD token can be obtained
print("\n📌 Test 1: Azure AD Token Generation")
print("-"*50)
try:
    credential = ClientSecretCredential(
        tenant_id=config['tenant_id'],
        client_id=config['client_id'],
        client_secret=config['client_secret']
    )
    
    # Try to get token for SQL/Synapse
    token = credential.get_token("https://database.windows.net/.default")
    print("✅ Successfully obtained Azure AD token")
    print(f"   Token expires at: {token.expires_on}")
    
except Exception as e:
    print(f"❌ Failed to get Azure AD token: {str(e)[:200]}")
    print("\nThis means the credentials are invalid or the service principal doesn't exist")
    sys.exit(1)

# Test 2: Try ODBC Driver 18 with Service Principal auth
print("\n📌 Test 2: Connection with ODBC Driver 18")
print("-"*50)

conn_str_18 = (
    f"DRIVER={{ODBC Driver 18 for SQL Server}};"
    f"SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;"
    f"DATABASE={config['database_name']};"
    f"UID={config['client_id']};"
    f"PWD={config['client_secret']};"
    f"Authentication=ActiveDirectoryServicePrincipal;"
    f"Encrypt=yes;"
    f"TrustServerCertificate=no;"
    f"Connection Timeout=30;"
)

print(f"Endpoint: {config['workspace_name']}-ondemand.sql.azuresynapse.net")

try:
    print("Attempting connection...")
    conn = pyodbc.connect(conn_str_18)
    cursor = conn.cursor()
    
    # Test query
    cursor.execute("SELECT DB_NAME() as db, CURRENT_TIMESTAMP as time, SUSER_NAME() as user_name")
    row = cursor.fetchone()
    
    print("✅ Connection SUCCESSFUL with ODBC Driver 18!")
    print(f"   Database: {row.db}")
    print(f"   Server time: {row.time}")
    print(f"   Connected as: {row.user_name}")
    
    cursor.close()
    conn.close()
    
except pyodbc.Error as e:
    print(f"❌ Connection FAILED with ODBC Driver 18")
    error_msg = str(e)
    print(f"   Error: {error_msg[:300]}")
    
    if "Login failed for user '<token-identified principal>'" in error_msg:
        print("\n⚠️  DIAGNOSIS: Token authentication failed")
        print("   This means the service principal doesn't have database access")
        print("\n   SOLUTION: Run this in Synapse Studio as admin:")
        print(f"   CREATE USER [{config['client_id']}] FROM EXTERNAL PROVIDER;")
        print(f"   ALTER ROLE db_datareader ADD MEMBER [{config['client_id']}];")
        print(f"   ALTER ROLE db_datawriter ADD MEMBER [{config['client_id']}];")
        
    elif "Login timeout expired" in error_msg:
        print("\n⚠️  DIAGNOSIS: Cannot reach the server")
        print("   Possible causes:")
        print("   1. Workspace name is incorrect")
        print("   2. Firewall is blocking the connection")
        print("   3. Workspace is paused or doesn't exist")
        
    elif "Invalid connection string" in error_msg:
        print("\n⚠️  DIAGNOSIS: Connection string format issue")

# Test 3: Try ODBC Driver 17 (as mentioned in the error)
print("\n📌 Test 3: Connection with ODBC Driver 17")
print("-"*50)

try:
    conn_str_17 = (
        f"DRIVER={{ODBC Driver 17 for SQL Server}};"
        f"SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;"
        f"DATABASE={config['database_name']};"
        f"UID={config['client_id']};"
        f"PWD={config['client_secret']};"
        f"Authentication=ActiveDirectoryServicePrincipal;"
        f"Encrypt=yes;"
        f"TrustServerCertificate=no;"
        f"Connection Timeout=30;"
    )
    
    print("Attempting connection with Driver 17...")
    conn = pyodbc.connect(conn_str_17)
    cursor = conn.cursor()
    
    cursor.execute("SELECT @@VERSION as version")
    row = cursor.fetchone()
    
    print("✅ Connection SUCCESSFUL with ODBC Driver 17!")
    print(f"   Server version: {str(row.version)[:100]}...")
    
    cursor.close()
    conn.close()
    
except pyodbc.Error as e:
    print(f"❌ Connection FAILED with ODBC Driver 17")
    print(f"   Error: {str(e)[:300]}")
except Exception as e:
    print(f"⚠️  ODBC Driver 17 might not be installed")
    print(f"   Error: {str(e)[:100]}")

# Test 4: Check available drivers
print("\n📌 Test 4: Available ODBC Drivers")
print("-"*50)
try:
    drivers = pyodbc.drivers()
    print(f"Available drivers: {drivers}")
    
    if 'ODBC Driver 18 for SQL Server' in drivers:
        print("✅ ODBC Driver 18 is installed")
    if 'ODBC Driver 17 for SQL Server' in drivers:
        print("✅ ODBC Driver 17 is installed")
        
except Exception as e:
    print(f"Error checking drivers: {e}")

print("\n" + "="*70)
print("📋 SUMMARY")
print("="*70)

print("\nIf connection failed with '<token-identified principal>' error:")
print("1. The service principal authentication is working (token obtained)")
print("2. But the database user doesn't exist")
print("\n🔧 FIX: Run this SQL in Synapse Studio:")
print("-"*50)
print(f"CREATE USER [{config['client_id']}] FROM EXTERNAL PROVIDER;")
print(f"ALTER ROLE db_datareader ADD MEMBER [{config['client_id']}];")
print(f"ALTER ROLE db_datawriter ADD MEMBER [{config['client_id']}];")
print("-"*50)
print("\nAlternatively, you can use the service principal name instead of client_id")
print("if you know the display name of your service principal.")