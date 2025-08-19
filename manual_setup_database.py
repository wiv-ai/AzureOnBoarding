#!/usr/bin/env python3
"""
Manual setup script to create database and user in Synapse
This simulates what the startup script should do
"""

import subprocess
import json
import time

# Configuration
WORKSPACE = "wiv-synapse-billing-21768"
RESOURCE_GROUP = "rg-wiv"
APP_ID = "52e9e7c8-5e81-4cc6-81c1-f8931a008f3f"

print("=" * 70)
print("🔧 MANUAL DATABASE SETUP FOR SYNAPSE")
print("=" * 70)
print(f"Workspace: {WORKSPACE}")
print(f"Resource Group: {RESOURCE_GROUP}")
print(f"Service Principal: {APP_ID}")
print("=" * 70)

# Step 1: Grant Synapse roles to service principal
print("\n📝 Step 1: Granting Synapse roles to service principal...")
roles = ["Synapse Administrator", "Synapse SQL Administrator"]

for role in roles:
    print(f"   Granting {role}...")
    cmd = [
        "az", "synapse", "role", "assignment", "create",
        "--workspace-name", WORKSPACE,
        "--role", role,
        "--assignee", APP_ID,
        "--resource-group", RESOURCE_GROUP,
        "--only-show-errors"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0:
        print(f"   ✅ {role} granted")
    else:
        if "already exists" in result.stderr or "Conflict" in result.stderr:
            print(f"   ✅ {role} already exists")
        else:
            print(f"   ⚠️ Could not grant {role}: {result.stderr[:100]}")

# Step 2: Create SQL script in Synapse workspace
print("\n📝 Step 2: Creating SQL script in Synapse workspace...")

sql_content = """
-- Create database if not exists
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics')
    CREATE DATABASE BillingAnalytics;
GO

USE BillingAnalytics;
GO

-- Create master key
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongP@ssw0rd2024!';
GO

-- Create user for service principal
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account')
    CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
GO

-- Grant permissions
ALTER ROLE db_datareader ADD MEMBER [wiv_account];
ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
GO

SELECT 'Database setup complete!' as Status;
"""

# Save SQL to file
with open("/tmp/setup_db.sql", "w") as f:
    f.write(sql_content)

script_name = f"SetupDatabase_{int(time.time())}"
cmd = [
    "az", "synapse", "sql-script", "create",
    "--workspace-name", WORKSPACE,
    "--name", script_name,
    "--file", "/tmp/setup_db.sql",
    "--resource-group", RESOURCE_GROUP,
    "--only-show-errors"
]

print(f"   Creating script: {script_name}")
result = subprocess.run(cmd, capture_output=True, text=True)
if result.returncode == 0:
    print(f"   ✅ SQL script created in Synapse Studio")
    print(f"   📌 Script name: {script_name}")
else:
    print(f"   ⚠️ Could not create script: {result.stderr[:200]}")

# Step 3: Try REST API approach
print("\n📝 Step 3: Attempting database creation via REST API...")

# Get access token
cmd = ["az", "account", "get-access-token", "--resource", "https://database.windows.net", "--query", "accessToken", "-o", "tsv"]
result = subprocess.run(cmd, capture_output=True, text=True)

if result.returncode == 0:
    token = result.stdout.strip()
    print("   ✅ Got Azure access token")
    
    # Create database
    import requests
    
    url = f"https://{WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/master/query"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }
    
    # Create database
    print("   Creating database...")
    query = {"query": "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'BillingAnalytics') CREATE DATABASE BillingAnalytics"}
    response = requests.post(url, headers=headers, json=query)
    
    if response.status_code in [200, 201, 202]:
        print("   ✅ Database created or already exists")
    else:
        print(f"   ⚠️ Database creation response: {response.status_code} - {response.text[:100]}")
    
    time.sleep(5)
    
    # Create user and grant permissions
    print("   Creating user and granting permissions...")
    url = f"https://{WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query"
    
    grant_sql = """
    IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'wiv_account')
        CREATE USER [wiv_account] FROM EXTERNAL PROVIDER;
    ALTER ROLE db_datareader ADD MEMBER [wiv_account];
    ALTER ROLE db_datawriter ADD MEMBER [wiv_account];
    ALTER ROLE db_ddladmin ADD MEMBER [wiv_account];
    """
    
    query = {"query": grant_sql}
    response = requests.post(url, headers=headers, json=query)
    
    if response.status_code in [200, 201, 202]:
        print("   ✅ User created and permissions granted")
    else:
        print(f"   ⚠️ User creation response: {response.status_code} - {response.text[:100]}")
else:
    print("   ⚠️ Could not get access token")

print("\n" + "=" * 70)
print("📋 NEXT STEPS:")
print("=" * 70)
print("1. Open Synapse Studio: https://web.azuresynapse.net")
print(f"2. Select workspace: {WORKSPACE}")
print(f"3. Go to Develop → SQL scripts → {script_name}")
print("4. Run the script")
print("\nOR")
print("\n5. Wait 1-2 minutes for roles to propagate")
print("6. Test with: python3 test_remote_query.py")
print("=" * 70)