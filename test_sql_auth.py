#!/usr/bin/env python3
"""
Test Synapse connection with SQL authentication
This is a fallback when Azure AD service principal isn't working
"""

import pyodbc
import sys

# SQL Authentication credentials (created in Synapse)
SQL_USER = "billing_reader"
SQL_PASSWORD = "BillingP@ss2024!"
WORKSPACE = "wiv-synapse-billing"
DATABASE = "BillingAnalytics"

def test_sql_auth():
    """Test connection with SQL authentication"""
    
    print("Testing SQL Authentication connection...")
    print(f"Workspace: {WORKSPACE}")
    print(f"Database: {DATABASE}")
    print(f"User: {SQL_USER}")
    print()
    
    # Connection string for SQL authentication
    conn_str = f"""
    DRIVER={{ODBC Driver 18 for SQL Server}};
    SERVER={WORKSPACE}-ondemand.sql.azuresynapse.net;
    DATABASE={DATABASE};
    UID={SQL_USER};
    PWD={SQL_PASSWORD};
    Encrypt=yes;
    TrustServerCertificate=no;
    Connection Timeout=30;
    """
    
    try:
        print("Attempting connection...")
        conn = pyodbc.connect(conn_str)
        cursor = conn.cursor()
        
        # Test query
        cursor.execute("SELECT DB_NAME() as db, USER_NAME() as usr, @@VERSION as ver")
        row = cursor.fetchone()
        
        print("✅ Connection successful!")
        print(f"   Database: {row.db}")
        print(f"   User: {row.usr}")
        print(f"   Server: {row.ver[:50]}...")
        
        # Test if we can query views
        cursor.execute("""
            SELECT name, type_desc 
            FROM sys.objects 
            WHERE type = 'V' AND schema_id = SCHEMA_ID('dbo')
        """)
        
        views = cursor.fetchall()
        if views:
            print(f"\n📊 Found {len(views)} view(s):")
            for view in views:
                print(f"   - {view.name}")
        else:
            print("\n📊 No views found yet")
        
        cursor.close()
        conn.close()
        
        print("\n✅ SQL Authentication is working!")
        print("\nTo use this in your scripts, update the connection string to:")
        print(f"   UID={SQL_USER}")
        print(f"   PWD={SQL_PASSWORD}")
        print("   (Remove Authentication=ActiveDirectoryServicePrincipal)")
        
        return True
        
    except pyodbc.Error as e:
        print(f"❌ Connection failed: {e}")
        print("\nTroubleshooting:")
        print("1. First run this SQL in Synapse Studio (BillingAnalytics database):")
        print(f"   CREATE USER [{SQL_USER}] WITH PASSWORD = '{SQL_PASSWORD}';")
        print(f"   ALTER ROLE db_datareader ADD MEMBER [{SQL_USER}];")
        print(f"   ALTER ROLE db_datawriter ADD MEMBER [{SQL_USER}];")
        print(f"   ALTER ROLE db_ddladmin ADD MEMBER [{SQL_USER}];")
        print("\n2. Then run this script again")
        return False

if __name__ == "__main__":
    success = test_sql_auth()
    sys.exit(0 if success else 1)