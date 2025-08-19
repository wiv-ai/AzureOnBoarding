#!/usr/bin/env python3
"""
Test Synapse connectivity using REST API
"""

import requests
from azure.identity import ClientSecretCredential
from synapse_config import SYNAPSE_CONFIG as config

print("Testing Synapse REST API connectivity...")
print(f"Workspace: {config['workspace_name']}")
print("-" * 50)

# Get Azure AD token
try:
    print("\n1. Getting Azure AD token...")
    credential = ClientSecretCredential(
        tenant_id=config['tenant_id'],
        client_id=config['client_id'],
        client_secret=config['client_secret']
    )
    
    # Get token for Synapse
    token = credential.get_token("https://dev.azuresynapse.net/.default")
    print("✅ Successfully obtained Azure AD token")
    
    # Test Synapse REST API
    print("\n2. Testing Synapse workspace REST API...")
    headers = {
        'Authorization': f'Bearer {token.token}',
        'Content-Type': 'application/json'
    }
    
    # Try to get workspace info
    workspace_url = f"https://{config['workspace_name']}.dev.azuresynapse.net"
    
    # Test SQL pools endpoint
    sql_pools_url = f"{workspace_url}/sqlPools"
    print(f"   Calling: {sql_pools_url}")
    
    response = requests.get(sql_pools_url, headers=headers)
    print(f"   Response status: {response.status_code}")
    
    if response.status_code == 200:
        print("✅ Successfully connected to Synapse workspace via REST API")
        pools = response.json()
        print(f"   SQL Pools found: {len(pools.get('value', []))}")
    elif response.status_code == 401:
        print("❌ Authentication failed - check service principal permissions")
    elif response.status_code == 404:
        print("❌ Workspace not found or endpoint incorrect")
    else:
        print(f"❌ Unexpected response: {response.status_code}")
        print(f"   Response: {response.text[:200]}")
    
    # Try to check if SQL On-Demand is accessible
    print("\n3. Checking SQL On-Demand endpoint...")
    ondemand_endpoint = f"{config['workspace_name']}-ondemand.sql.azuresynapse.net"
    print(f"   Endpoint: {ondemand_endpoint}")
    
    # Note: SQL On-Demand uses different authentication, but we can check if it resolves
    import socket
    try:
        ip = socket.gethostbyname(ondemand_endpoint)
        print(f"✅ SQL On-Demand endpoint resolves to: {ip}")
    except socket.gaierror:
        print("❌ SQL On-Demand endpoint does not resolve - check workspace name")
    
except Exception as e:
    print(f"❌ Error: {str(e)}")
    
print("\n" + "=" * 50)
print("Summary:")
print("- If REST API works but SQL connection fails: Firewall issue")
print("- If both fail: Service principal permissions issue")
print("- Check Azure Portal > Synapse workspace > Networking > Firewall rules")