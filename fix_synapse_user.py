#!/usr/bin/env python3
"""
Fix Synapse database user permissions for service principal
This script creates the missing database user that causes the 
'Login failed for user <token-identified principal>' error
"""

import pyodbc
import sys
from synapse_config import SYNAPSE_CONFIG

def fix_database_user():
    """Create database user and grant permissions"""
    
    config = SYNAPSE_CONFIG
    
    # First, we need to use SQL Admin credentials to create the user
    # Since we don't have those, we'll provide the SQL commands to run manually
    
    print("=" * 70)
    print("🔧 FIX FOR SYNAPSE AUTHENTICATION ERROR")
    print("=" * 70)
    print()
    print("The service principal is missing database-level permissions.")
    print("Run these SQL commands in Synapse Studio as admin:")
    print()
    print("1. Open Azure Portal and navigate to your Synapse workspace:")
    print(f"   Workspace: {config['workspace_name']}")
    print()
    print("2. Click 'Open Synapse Studio'")
    print()
    print("3. Go to 'Develop' hub → New SQL script")
    print()
    print("4. IMPORTANT: Select 'BillingAnalytics' database (NOT master!)")
    print("   In the toolbar, change from 'master' to 'BillingAnalytics'")
    print()
    print("5. Run these commands:")
    print()
    print("-" * 70)
    print(f"""
-- IMPORTANT: Make sure you're connected to BillingAnalytics database, not master!
USE BillingAnalytics;
GO

-- Create database user for the service principal
CREATE USER [{config['client_id']}] FROM EXTERNAL PROVIDER;

-- Grant necessary permissions
ALTER ROLE db_datareader ADD MEMBER [{config['client_id']}];
ALTER ROLE db_datawriter ADD MEMBER [{config['client_id']}];
ALTER ROLE db_ddladmin ADD MEMBER [{config['client_id']}];

-- Verify the user was created
SELECT name, type_desc, authentication_type_desc 
FROM sys.database_principals 
WHERE name = '{config['client_id']}';
""")
    print("-" * 70)
    print()
    print("After running these commands, test_billing_queries.py will work!")
    print()
    
    # Try to test if it's already fixed
    print("Testing current connection status...")
    conn_str = f"""
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
        conn = pyodbc.connect(conn_str)
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.close()
        conn.close()
        print("✅ Connection successful! The user already has permissions.")
        return True
    except pyodbc.Error as e:
        if "Login failed for user '<token-identified principal>'" in str(e):
            print("❌ User still needs database permissions. Run the SQL above.")
        else:
            print(f"❌ Error: {str(e)[:200]}")
        return False

if __name__ == "__main__":
    success = fix_database_user()
    sys.exit(0 if success else 1)