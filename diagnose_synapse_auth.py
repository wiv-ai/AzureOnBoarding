#!/usr/bin/env python3
"""
Comprehensive Synapse Authentication Diagnostic Tool
Tests authentication using synapse_config.py and identifies specific issues
"""

import pyodbc
import sys
import time
from datetime import datetime

# Load configuration
try:
    from synapse_config import SYNAPSE_CONFIG as config
    print("✅ Loaded configuration from synapse_config.py")
except ImportError:
    print("❌ Error: synapse_config.py not found")
    sys.exit(1)

def print_header(title):
    """Print a formatted header"""
    print("\n" + "=" * 70)
    print(f"🔍 {title}")
    print("=" * 70)

def print_test(test_name):
    """Print test section header"""
    print(f"\n📋 {test_name}")
    print("-" * 50)

def test_connection(conn_str, description, database_name=None):
    """Test database connection and return connection object if successful"""
    print(f"   Testing: {description}")
    try:
        conn = pyodbc.connect(conn_str, timeout=30)
        print(f"   ✅ SUCCESS: Connected to {database_name or 'database'}")
        return conn
    except pyodbc.Error as e:
        error_msg = str(e)
        print(f"   ❌ FAILED: {error_msg[:100]}...")
        
        # Analyze specific error types
        if "Login failed" in error_msg:
            print("   📝 Analysis: Authentication failed - likely missing database user")
        elif "timeout" in error_msg.lower():
            print("   📝 Analysis: Connection timeout - likely firewall or network issue")
        elif "does not exist" in error_msg.lower():
            print("   📝 Analysis: Database doesn't exist")
        elif "Access denied" in error_msg:
            print("   📝 Analysis: Permission denied - check RBAC roles")
        
        return None

def diagnose_synapse_authentication():
    """Main diagnostic function"""
    print_header("SYNAPSE AUTHENTICATION DIAGNOSTIC")
    
    # Display configuration
    print(f"Workspace: {config['workspace_name']}")
    print(f"Database: BillingAnalytics")
    print(f"Service Principal: {config['app_id']}")
    print(f"Tenant: {config['tenant_id']}")
    
    # Test 1: Connection to master database
    print_test("Test 1: Master Database Access")
    master_conn_str = f"""
    DRIVER={{ODBC Driver 18 for SQL Server}};
    SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;
    DATABASE=master;
    UID={config['app_id']};
    PWD={config['client_secret']};
    Authentication=ActiveDirectoryServicePrincipal;
    Encrypt=yes;
    TrustServerCertificate=no;
    Connection Timeout=30;
    """
    
    master_conn = test_connection(master_conn_str, "Master database connection", "master")
    
    if master_conn:
        try:
            cursor = master_conn.cursor()
            
            # Check if BillingAnalytics database exists
            cursor.execute("SELECT name FROM sys.databases WHERE name = 'BillingAnalytics'")
            db_exists = cursor.fetchone()
            
            if db_exists:
                print(f"   ✅ Database 'BillingAnalytics' exists")
            else:
                print(f"   ❌ Database 'BillingAnalytics' does not exist")
                print(f"   📝 Solution: Create database 'BillingAnalytics' first")
            
            # List all databases
            cursor.execute("SELECT name FROM sys.databases ORDER BY name")
            databases = cursor.fetchall()
            print(f"   📋 Available databases: {[db[0] for db in databases]}")
            
            cursor.close()
            master_conn.close()
            
        except Exception as e:
            print(f"   ⚠️  Error querying master: {str(e)[:100]}")
    
    # Test 2: Connection to target database
    print_test("Test 2: Target Database Access")
    target_conn_str = f"""
    DRIVER={{ODBC Driver 18 for SQL Server}};
    SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;
    DATABASE=BillingAnalytics;
    UID={config['app_id']};
    PWD={config['client_secret']};
    Authentication=ActiveDirectoryServicePrincipal;
    Encrypt=yes;
    TrustServerCertificate=no;
    Connection Timeout=30;
    """
    
    target_conn = test_connection(target_conn_str, "BillingAnalytics database connection", "BillingAnalytics")
    
    if target_conn:
        try:
            cursor = target_conn.cursor()
            
            # Check current user and login
            cursor.execute("SELECT USER_NAME() as [current_user], SUSER_NAME() as [login_name]")
            user_info = cursor.fetchone()
            print(f"   👤 Current user: {user_info[0]}")
            print(f"   🔑 Login name: {user_info[1]}")
            
            # Check database users
            cursor.execute("SELECT name, type_desc, authentication_type_desc FROM sys.database_principals WHERE type IN ('S', 'E', 'X') ORDER BY name")
            users = cursor.fetchall()
            
            print(f"   👥 Database users ({len(users)} found):")
            for user in users:
                print(f"      - {user[0]} ({user[1]}, {user[2]})")
            
            # Check if wiv_account user exists
            wiv_user_exists = any(user[0] == 'wiv_account' for user in users)
            if wiv_user_exists:
                print("   ✅ Database user 'wiv_account' exists")
            else:
                print("   ❌ Database user 'wiv_account' does not exist")
            
            # Check if BillingData view exists
            cursor.execute("SELECT COUNT(*) FROM sys.views WHERE name = 'BillingData'")
            view_exists = cursor.fetchone()[0] > 0
            
            if view_exists:
                print("   ✅ BillingData view exists")
                
                # Try to query the view
                cursor.execute("SELECT COUNT(*) FROM BillingData")
                record_count = cursor.fetchone()[0]
                print(f"   📊 BillingData view has {record_count} records")
            else:
                print("   ❌ BillingData view does not exist")
            
            cursor.close()
            target_conn.close()
            
            print("\n🎉 ALL TESTS PASSED - Authentication is working!")
            return True
            
        except Exception as e:
            print(f"   ⚠️  Error querying target database: {str(e)}")
            # Try to get more details about the error
            if hasattr(e, 'args') and len(e.args) > 0:
                print(f"   📝 Full error details: {e.args[0]}")
    
    # Test 3: Check firewall and network connectivity
    print_test("Test 3: Network Connectivity")
    print("   🌐 Checking if workspace endpoint is reachable...")
    
    try:
        import socket
        endpoint = f"{config['workspace_name']}-ondemand.sql.azuresynapse.net"
        socket.create_connection((endpoint, 1433), timeout=10)
        print(f"   ✅ Network connectivity to {endpoint}:1433 is working")
    except Exception as e:
        print(f"   ❌ Network connectivity failed: {str(e)}")
        print("   📝 Solution: Check firewall rules in Synapse workspace")
    
    # Summary and recommendations
    print_header("DIAGNOSTIC SUMMARY")
    
    if not master_conn:
        print("❌ CRITICAL: Cannot connect to master database")
        print("📋 Recommended actions:")
        print("   1. Verify service principal has Synapse Administrator role")
        print("   2. Check firewall rules in Synapse workspace")
        print("   3. Verify service principal credentials are correct")
        
    elif not target_conn:
        print("⚠️  PARTIAL: Can connect to master but not target database")
        print("📋 Most likely cause: Missing database user")
        print("📋 Recommended actions:")
        print("   1. Open Synapse Studio: https://web.azuresynapse.net")
        print(f"   2. Select workspace: {config['workspace_name']}")
        print("   3. Run the SQL commands in fix_synapse_user.sql")
        
    else:
        print("✅ SUCCESS: All connections working")
    
    return False

def generate_fix_commands():
    """Generate SQL commands to fix authentication issues"""
    print_header("FIX COMMANDS")
    
    sql_commands = f"""
-- Fix Synapse Authentication Issues
-- Run these commands in Synapse Studio

-- Step 1: Ensure database exists
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = '{config['database_name']}')
    CREATE DATABASE {config['database_name']};
GO

-- Step 2: Use the target database
USE {config['database_name']};
GO

-- Step 3: Create master key if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd2024!';
GO

-- Step 4: Create credential for external data source
IF NOT EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'WorkspaceIdentity')
    CREATE DATABASE SCOPED CREDENTIAL WorkspaceIdentity 
    WITH IDENTITY = 'Managed Identity';
GO

-- Step 5: Create database user for service principal
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account')
    CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
GO

-- Step 6: Grant permissions
ALTER ROLE db_datareader ADD MEMBER [wiv_account];
ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
GO

-- Step 7: Verify user was created
SELECT name, type_desc, authentication_type_desc 
FROM sys.database_principals 
WHERE name = 'wiv_account';
GO

-- Step 8: Test connection
SELECT USER_NAME() as [current_user], SUSER_NAME() as [login_name], DB_NAME() as [database_name];
GO
"""
    
    print("📝 SQL Commands to run in Synapse Studio:")
    print("-" * 70)
    print(sql_commands)
    
    # Write to file
    with open('fix_synapse_user.sql', 'w') as f:
        f.write(sql_commands)
    print("\n💾 Commands saved to: fix_synapse_user.sql")

if __name__ == "__main__":
    print(f"🚀 Starting Synapse Authentication Diagnostic")
    print(f"⏰ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    success = diagnose_synapse_authentication()
    
    if not success:
        generate_fix_commands()
        
        print_header("NEXT STEPS")
        print("1. Open Synapse Studio: https://web.azuresynapse.net")
        print(f"2. Select workspace: {config['workspace_name']}")
        print("3. Run the SQL commands from fix_synapse_user.sql")
        print("4. Re-run this diagnostic to verify the fix")
    else:
        print("\n🎉 No issues found! Your authentication is working correctly.")
        print("You should now be able to run queries against your Synapse database.")
