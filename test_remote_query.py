#!/usr/bin/env python3
"""
Test script for Synapse remote query functionality
"""

import sys
import os

# Test if we can import the client
try:
    from synapse_remote_query_client import SynapseAPIClient
    print("✅ Successfully imported SynapseAPIClient")
except ImportError as e:
    print(f"❌ Failed to import: {e}")
    sys.exit(1)

# Test configuration
print("\n📊 Testing Synapse Remote Query Client")
print("=" * 50)

# Try to load config from synapse_config.py if it exists
try:
    from synapse_config import SYNAPSE_CONFIG
    config = SYNAPSE_CONFIG
    print("✅ Using configuration from synapse_config.py")
except ImportError:
    # Use the test configuration
    config = {
        'tenant_id': 'ba153ff0-3397-4ef5-a214-dd33e8c37bff',
        'client_id': '554b11c1-18f9-46b5-a096-30e0a2cfae6f',
        'client_secret': 'tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams',
        'workspace_name': 'wiv-synapse-billing',
        'database_name': 'BillingAnalytics'
    }
    print("⚠️  Using default test configuration")

print(f"Workspace: {config['workspace_name']}")
print(f"Database: {config.get('database_name', 'BillingAnalytics')}")

# Initialize client
try:
    client = SynapseAPIClient(
        tenant_id=config['tenant_id'],
        client_id=config['client_id'],
        client_secret=config['client_secret'],
        workspace_name=config['workspace_name'],
        database_name=config.get('database_name', 'BillingAnalytics')
    )
    print("✅ Client initialized successfully")
except Exception as e:
    print(f"❌ Failed to initialize client: {e}")
    sys.exit(1)

# Test 1: Check if pyodbc is available
print("\n1️⃣ Checking pyodbc availability...")
try:
    import pyodbc
    print("✅ pyodbc is installed")
    
    # List available drivers
    drivers = pyodbc.drivers()
    print(f"   Available ODBC drivers: {drivers}")
    
    if 'ODBC Driver 18 for SQL Server' in drivers:
        print("   ✅ SQL Server ODBC Driver 18 is installed")
    elif 'ODBC Driver 17 for SQL Server' in drivers:
        print("   ⚠️  SQL Server ODBC Driver 17 found (18 recommended)")
    else:
        print("   ❌ No SQL Server ODBC driver found")
        print("   Install with: ")
        print("   macOS: brew install msodbcsql18")
        print("   Ubuntu: sudo apt-get install msodbcsql18")
        
except ImportError:
    print("❌ pyodbc not installed")
    print("   Install with: pip install pyodbc")
    sys.exit(1)

# Test 2: Try a simple query
print("\n2️⃣ Testing connection with simple query...")
try:
    # Test with a simple metadata query first
    test_query = "SELECT DB_NAME() as DatabaseName, CURRENT_TIMESTAMP as CurrentTime"
    
    conn_str = (
        f"DRIVER={{ODBC Driver 18 for SQL Server}};"
        f"SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;"
        f"DATABASE={config.get('database_name', 'BillingAnalytics')};"
        f"UID={config['client_id']};"
        f"PWD={config['client_secret']};"
        f"Authentication=ActiveDirectoryServicePrincipal;"
        f"Encrypt=yes;"
        f"TrustServerCertificate=no;"
    )
    
    conn = pyodbc.connect(conn_str)
    cursor = conn.cursor()
    cursor.execute(test_query)
    row = cursor.fetchone()
    print(f"✅ Connected to: {row[0]} at {row[1]}")
    cursor.close()
    conn.close()
    
except Exception as e:
    print(f"❌ Connection failed: {str(e)[:200]}")
    print("\nPossible issues:")
    print("1. Service principal credentials may be incorrect")
    print("2. Synapse workspace may not be accessible")
    print("3. Database may not exist")
    print("4. Firewall rules may be blocking access")
    sys.exit(1)

# Test 3: Test the actual query methods
print("\n3️⃣ Testing query methods...")

# Test get_daily_costs
print("\n   Testing get_daily_costs(days_back=7)...")
try:
    df = client.get_daily_costs(days_back=7)
    if df is not None and not df.empty:
        print(f"   ✅ Retrieved {len(df)} days of data")
        print(f"   Sample data:")
        print(df.head(3).to_string())
    elif df is not None and df.empty:
        print("   ⚠️  Query succeeded but no data returned")
        print("   This is normal if no billing data has been exported yet")
    else:
        print("   ❌ Query returned None")
except Exception as e:
    print(f"   ❌ Query failed: {str(e)[:200]}")

# Test query_billing_summary
print("\n   Testing query_billing_summary()...")
try:
    df = client.query_billing_summary()
    if df is not None and not df.empty:
        print(f"   ✅ Retrieved {len(df)} resource groups")
        print(f"   Top 3 by cost:")
        print(df.head(3).to_string())
    elif df is not None and df.empty:
        print("   ⚠️  Query succeeded but no data returned")
    else:
        print("   ❌ Query returned None")
except Exception as e:
    print(f"   ❌ Query failed: {str(e)[:200]}")

# Test 4: Check if the BillingData view exists
print("\n4️⃣ Checking if BillingData view exists...")
try:
    check_view_query = """
    SELECT COUNT(*) as ViewExists
    FROM sys.views 
    WHERE name = 'BillingData'
    """
    
    conn = pyodbc.connect(conn_str)
    cursor = conn.cursor()
    cursor.execute(check_view_query)
    row = cursor.fetchone()
    
    if row[0] > 0:
        print("✅ BillingData view exists")
        
        # Try to get record count
        cursor.execute("SELECT COUNT(*) as RecordCount FROM BillingData")
        row = cursor.fetchone()
        print(f"   Records in view: {row[0]}")
        
        if row[0] == 0:
            print("   ⚠️  No data in view yet. Billing export may not have run.")
            print("   Data will appear after the first export completes (5-30 minutes)")
    else:
        print("❌ BillingData view does not exist")
        print("   Run the setup script or create the view manually in Synapse Studio")
    
    cursor.close()
    conn.close()
    
except Exception as e:
    print(f"❌ Failed to check view: {str(e)[:200]}")

print("\n" + "=" * 50)
print("📊 Remote Query Test Complete")
print("=" * 50)

# Summary
print("\nSummary:")
print(f"  Workspace: {config['workspace_name']}")
print(f"  Database: {config.get('database_name', 'BillingAnalytics')}")
print(f"  Endpoint: {config['workspace_name']}-ondemand.sql.azuresynapse.net")
print("\nIf queries are failing, check:")
print("1. Billing export has run (wait 5-30 minutes after setup)")
print("2. Service principal has Synapse access")
print("3. Database and view exist")
print("4. Firewall allows your IP")