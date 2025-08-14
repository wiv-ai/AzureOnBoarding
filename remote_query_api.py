#!/usr/bin/env python3
"""
Remote Synapse Query Script
Executes queries on Azure Synapse remotely via REST API
"""

import requests
import json
import time
from datetime import datetime

# Configuration
TENANT_ID = "ba153ff0-3397-4ef5-a214-dd33e8c37bff"
CLIENT_ID = "030cce2a-e94a-4d6f-9455-f8577c1721cb"
CLIENT_SECRET = "Kxk8Q~LzvG1jl9halVfv4OH.ZgSshbZER108Hcuh"  # You may need to update this
SYNAPSE_WORKSPACE = "wiv-synapse-billing"
STORAGE_ACCOUNT = "billingstorage73919"

def get_access_token():
    """Get Azure AD access token for Synapse"""
    url = f"https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token"
    
    payload = {
        'client_id': CLIENT_ID,
        'client_secret': CLIENT_SECRET,
        'scope': 'https://dev.azuresynapse.net/.default',
        'grant_type': 'client_credentials'
    }
    
    response = requests.post(url, data=payload)
    
    if response.status_code == 200:
        return response.json()['access_token']
    else:
        print(f"Failed to get token: {response.text}")
        return None

def execute_synapse_query(query, database="master"):
    """Execute a query on Synapse SQL serverless pool"""
    
    # Get access token
    token = get_access_token()
    if not token:
        return None
    
    # Synapse SQL endpoint
    endpoint = f"https://{SYNAPSE_WORKSPACE}.sql.azuresynapse.net:1443"
    
    # Headers for the request
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    
    # Use the REST API to execute query
    url = f"{endpoint}/sql/pools/Built-in/jobs"
    
    payload = {
        "properties": {
            "query": query,
            "database": database
        }
    }
    
    # Submit the query
    response = requests.post(url, headers=headers, json=payload)
    
    if response.status_code in [200, 201, 202]:
        job_id = response.json().get('id')
        print(f"Query submitted. Job ID: {job_id}")
        
        # Poll for results
        result_url = f"{endpoint}/sql/pools/Built-in/jobs/{job_id}"
        
        for _ in range(30):  # Poll for up to 30 seconds
            time.sleep(1)
            result_response = requests.get(result_url, headers=headers)
            
            if result_response.status_code == 200:
                result = result_response.json()
                if result.get('properties', {}).get('status') == 'Succeeded':
                    return result.get('properties', {}).get('result')
                elif result.get('properties', {}).get('status') == 'Failed':
                    print(f"Query failed: {result.get('properties', {}).get('error')}")
                    return None
        
        print("Query timeout")
        return None
    else:
        print(f"Failed to execute query: {response.text}")
        return None

def query_billing_data():
    """Query billing data from Synapse"""
    
    # Simple query to test connection
    test_query = "SELECT GETDATE() as CurrentTime, DB_NAME() as DatabaseName"
    
    print("Testing Synapse connection...")
    result = execute_synapse_query(test_query)
    
    if result:
        print(f"Connection successful: {result}")
    else:
        print("Connection failed")
        return
    
    # Query billing data
    billing_query = f"""
    SELECT TOP 10 *
    FROM OPENROWSET(
        BULK 'https://{STORAGE_ACCOUNT}.blob.core.windows.net/billing-exports/DailyBillingExport_b25100c0-b66f-4391-ae32-2661f9e8e729.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        FIRSTROW = 2
    ) 
    WITH (
        Date NVARCHAR(100),
        ServiceFamily NVARCHAR(100),
        ResourceGroup NVARCHAR(100),
        CostInUSD NVARCHAR(50)
    ) AS BillingData
    """
    
    print("\nQuerying billing data...")
    result = execute_synapse_query(billing_query)
    
    if result:
        print("Billing data retrieved successfully:")
        print(json.dumps(result, indent=2))
    else:
        print("Failed to retrieve billing data")

# Alternative method using pyodbc
def query_with_pyodbc():
    """Alternative method using ODBC connection"""
    try:
        import pyodbc
        
        # Connection string for Azure Synapse
        conn_str = (
            f"DRIVER={{ODBC Driver 17 for SQL Server}};"
            f"SERVER={SYNAPSE_WORKSPACE}.sql.azuresynapse.net,1433;"
            f"DATABASE=master;"
            f"UID={CLIENT_ID};"
            f"PWD={CLIENT_SECRET};"
            f"Authentication=ActiveDirectoryServicePrincipal;"
        )
        
        print("Connecting via ODBC...")
        conn = pyodbc.connect(conn_str)
        cursor = conn.cursor()
        
        # Test query
        cursor.execute("SELECT GETDATE() as CurrentTime")
        row = cursor.fetchone()
        print(f"Connected! Current time: {row[0]}")
        
        # Billing query
        billing_query = f"""
        SELECT TOP 10 *
        FROM OPENROWSET(
            BULK 'https://{STORAGE_ACCOUNT}.blob.core.windows.net/billing-exports/DailyBillingExport_b25100c0-b66f-4391-ae32-2661f9e8e729.csv',
            FORMAT = 'CSV',
            PARSER_VERSION = '2.0',
            FIRSTROW = 2
        ) 
        WITH (
            Date NVARCHAR(100),
            ServiceFamily NVARCHAR(100),
            ResourceGroup NVARCHAR(100),
            CostInUSD NVARCHAR(50)
        ) AS BillingData
        """
        
        cursor.execute(billing_query)
        
        # Fetch results
        columns = [column[0] for column in cursor.description]
        results = []
        for row in cursor.fetchall():
            results.append(dict(zip(columns, row)))
        
        print(f"\nBilling data ({len(results)} rows):")
        for row in results[:5]:  # Show first 5 rows
            print(row)
        
        cursor.close()
        conn.close()
        
    except Exception as e:
        print(f"ODBC connection failed: {e}")
        print("\nTo use ODBC, install: pip install pyodbc")
        print("And ensure ODBC Driver 17 for SQL Server is installed")

if __name__ == "__main__":
    print("=" * 50)
    print("Remote Synapse Query Tool")
    print("=" * 50)
    print(f"Workspace: {SYNAPSE_WORKSPACE}")
    print(f"Storage: {STORAGE_ACCOUNT}")
    print("=" * 50)
    
    # Method 1: REST API
    print("\nMethod 1: Using REST API")
    print("-" * 30)
    query_billing_data()
    
    # Method 2: ODBC (if available)
    print("\n" + "=" * 50)
    print("Method 2: Using ODBC")
    print("-" * 30)
    query_with_pyodbc()