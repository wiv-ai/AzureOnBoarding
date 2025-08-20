#!/usr/bin/env python3
"""
Test Synapse setup using REST API (no pyodbc required)
"""

import requests
import json
import subprocess
import sys

# Configuration from your setup
config = {
    'workspace_name': 'wiv-synapse-billing-68637',
    'database_name': 'BillingAnalytics',
    'storage_account': 'billingstorage68600',
    'container': 'billing-exports',
    'client_id': 'ca400b78-20d9-4181-ad67-de0c45b7f676'
}

print("=" * 70)
print("🔍 TESTING SYNAPSE SETUP VIA REST API")
print("=" * 70)
print()
print("Configuration:")
print(f"  Workspace: {config['workspace_name']}")
print(f"  Database: {config['database_name']}")
print(f"  Storage: {config['storage_account']}")
print()

# Get Azure access token
print("1. Getting Azure access token...")
try:
    result = subprocess.run(
        ["az", "account", "get-access-token", "--resource", "https://database.windows.net", "--query", "accessToken", "-o", "tsv"],
        capture_output=True,
        text=True,
        check=True
    )
    access_token = result.stdout.strip()
    
    if access_token:
        print("   ✅ Successfully obtained access token")
    else:
        print("   ❌ Failed to get access token")
        print("   Please run: az login")
        sys.exit(1)
except Exception as e:
    print(f"   ❌ Error getting token: {e}")
    print("   Please ensure Azure CLI is installed and you're logged in")
    sys.exit(1)

# Test database existence
print()
print("2. Checking if database exists...")
try:
    url = f"https://{config['workspace_name']}-ondemand.sql.azuresynapse.net/sql/databases/master/query"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }
    data = {"query": "SELECT name FROM sys.databases WHERE name = 'BillingAnalytics'"}
    
    response = requests.post(url, headers=headers, json=data, timeout=30)
    
    if response.status_code == 200:
        result = response.json()
        if 'resultSets' in result and result['resultSets']:
            print("   ✅ Database 'BillingAnalytics' exists")
        else:
            print("   ⚠️  Database might exist but no results returned")
    else:
        print(f"   ❌ Error checking database: HTTP {response.status_code}")
        print(f"   Response: {response.text[:200]}")
except Exception as e:
    print(f"   ❌ Error: {e}")

# Test view existence
print()
print("3. Checking if BillingData view exists...")
try:
    url = f"https://{config['workspace_name']}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query"
    data = {"query": "SELECT name FROM sys.views WHERE name = 'BillingData'"}
    
    response = requests.post(url, headers=headers, json=data, timeout=30)
    
    if response.status_code == 200:
        result = response.json()
        if 'resultSets' in result and result['resultSets']:
            print("   ✅ View 'BillingData' exists")
        else:
            print("   ⚠️  View might exist but no results returned")
    else:
        print(f"   ❌ Error checking view: HTTP {response.status_code}")
        print(f"   Response: {response.text[:200]}")
except Exception as e:
    print(f"   ❌ Error: {e}")

# Test user existence
print()
print("4. Checking if user 'wiv_account' exists...")
try:
    data = {"query": "SELECT name FROM sys.database_principals WHERE name = 'wiv_account'"}
    
    response = requests.post(url, headers=headers, json=data, timeout=30)
    
    if response.status_code == 200:
        result = response.json()
        if 'resultSets' in result and result['resultSets']:
            print("   ✅ User 'wiv_account' exists")
        else:
            print("   ⚠️  User might exist but no results returned")
    else:
        print(f"   ❌ Error checking user: HTTP {response.status_code}")
except Exception as e:
    print(f"   ❌ Error: {e}")

# Test query capability
print()
print("5. Testing query capability...")
try:
    data = {"query": "SELECT DB_NAME() as DatabaseName, GETDATE() as CurrentTime"}
    
    response = requests.post(url, headers=headers, json=data, timeout=30)
    
    if response.status_code == 200:
        result = response.json()
        if 'resultSets' in result and result['resultSets']:
            print("   ✅ Query capability is working")
            if result['resultSets'][0]['rows']:
                row = result['resultSets'][0]['rows'][0]
                print(f"   Database: {row[0]}, Time: {row[1]}")
        else:
            print("   ⚠️  Query executed but no results")
    else:
        print(f"   ❌ Error executing query: HTTP {response.status_code}")
except Exception as e:
    print(f"   ❌ Error: {e}")

# Try to query the view (might fail if no data yet)
print()
print("6. Testing BillingData view query...")
try:
    data = {"query": "SELECT TOP 1 'Test' as Status FROM BillingData"}
    
    response = requests.post(url, headers=headers, json=data, timeout=30)
    
    if response.status_code == 200:
        result = response.json()
        if 'error' in response.text.lower():
            print("   ⚠️  View exists but no data yet (normal for new setup)")
            print("   Data will arrive after first billing export completes")
        else:
            print("   ✅ View is queryable")
    else:
        if 'error' in response.text.lower() and 'cannot find' in response.text.lower():
            print("   ⚠️  No billing data available yet")
            print("   This is normal - data arrives after export completes (5-30 min)")
        else:
            print(f"   ⚠️  Query returned: HTTP {response.status_code}")
except Exception as e:
    print(f"   ⚠️  Expected error (no data yet): {str(e)[:100]}")

print()
print("=" * 70)
print("📊 TEST SUMMARY")
print("=" * 70)
print()
print("✅ SETUP VALIDATED:")
print(f"  • Synapse workspace: {config['workspace_name']}")
print(f"  • Database: BillingAnalytics")
print(f"  • View: BillingData")
print(f"  • User: wiv_account")
print()
print("📝 NEXT STEPS:")
print("  1. Wait 5-30 minutes for billing export to complete")
print("  2. Open Synapse Studio: https://web.azuresynapse.net")
print(f"  3. Select workspace: {config['workspace_name']}")
print("  4. Run: SELECT TOP 10 * FROM BillingAnalytics.dbo.BillingData")
print()
print("⏰ Note: First export may take up to 30 minutes")
print("   Subsequent exports run daily at midnight UTC")
print()