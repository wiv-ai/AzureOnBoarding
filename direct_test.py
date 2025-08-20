#!/usr/bin/env python3
import json
import urllib.request
import urllib.parse
import ssl

# Your credentials
TENANT_ID = "ba153ff0-3397-4ef5-a214-dd33e8c37bff"
CLIENT_ID = "ca400b78-20d9-4181-ad67-de0c45b7f676"
CLIENT_SECRET = "fhX8Q~RmVyP13d.ZA1hGf27RW2jmOxRCnKI5Pccw"
WORKSPACE = "wiv-synapse-billing-68637"

print("=" * 70)
print("TESTING SYNAPSE SETUP DIRECTLY")
print("=" * 70)
print()

# Get access token using service principal
print("1. Getting access token using service principal...")
token_url = f"https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token"
token_data = urllib.parse.urlencode({
    'client_id': CLIENT_ID,
    'client_secret': CLIENT_SECRET,
    'scope': 'https://database.windows.net/.default',
    'grant_type': 'client_credentials'
}).encode()

try:
    req = urllib.request.Request(token_url, data=token_data)
    with urllib.request.urlopen(req) as response:
        token_response = json.loads(response.read())
        access_token = token_response['access_token']
        print("   ✅ Got access token")
except Exception as e:
    print(f"   ❌ Failed to get token: {e}")
    exit(1)

# Test database existence
print()
print("2. Checking if database BillingAnalytics exists...")
db_url = f"https://{WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/master/query"
headers = {
    'Authorization': f'Bearer {access_token}',
    'Content-Type': 'application/json'
}
query_data = json.dumps({"query": "SELECT name FROM sys.databases WHERE name = 'BillingAnalytics'"}).encode()

try:
    req = urllib.request.Request(db_url, data=query_data, headers=headers)
    with urllib.request.urlopen(req) as response:
        result = json.loads(response.read())
        if 'resultSets' in result and result['resultSets'] and result['resultSets'][0]['rows']:
            print("   ✅ Database BillingAnalytics EXISTS")
        else:
            print("   ❌ Database BillingAnalytics NOT FOUND")
            print(f"   Response: {json.dumps(result, indent=2)}")
except Exception as e:
    print(f"   ❌ Error checking database: {e}")

# Check view
print()
print("3. Checking if view BillingData exists...")
view_url = f"https://{WORKSPACE}-ondemand.sql.azuresynapse.net/sql/databases/BillingAnalytics/query"
view_query = json.dumps({"query": "SELECT name FROM sys.views WHERE name = 'BillingData'"}).encode()

try:
    req = urllib.request.Request(view_url, data=view_query, headers=headers)
    with urllib.request.urlopen(req) as response:
        result = json.loads(response.read())
        if 'resultSets' in result and result['resultSets'] and result['resultSets'][0]['rows']:
            print("   ✅ View BillingData EXISTS")
        else:
            print("   ❌ View BillingData NOT FOUND")
            print(f"   Response: {json.dumps(result, indent=2)}")
except urllib.error.HTTPError as e:
    error_body = e.read().decode()
    if "Database 'BillingAnalytics' does not exist" in error_body:
        print("   ❌ Database doesn't exist, so view can't exist")
    else:
        print(f"   ❌ Error: {error_body[:200]}")
except Exception as e:
    print(f"   ❌ Error checking view: {e}")

# Check user
print()
print("4. Checking if user wiv_account exists...")
user_query = json.dumps({"query": "SELECT name FROM sys.database_principals WHERE name = 'wiv_account'"}).encode()

try:
    req = urllib.request.Request(view_url, data=user_query, headers=headers)
    with urllib.request.urlopen(req) as response:
        result = json.loads(response.read())
        if 'resultSets' in result and result['resultSets'] and result['resultSets'][0]['rows']:
            print("   ✅ User wiv_account EXISTS")
        else:
            print("   ❌ User wiv_account NOT FOUND")
except Exception as e:
    print(f"   ❌ Error checking user: {e}")

print()
print("=" * 70)
print("TEST RESULTS")
print("=" * 70)
