import pyodbc
import time

print("Testing direct connection with longer timeout...")

# Try with 60 second timeout
conn_str = """
DRIVER={ODBC Driver 18 for SQL Server};
SERVER=wiv-synapse-billing-ondemand.sql.azuresynapse.net;
DATABASE=master;
UID=554b11c1-18f9-46b5-a096-30e0a2cfae6f;
PWD=tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams;
Authentication=ActiveDirectoryServicePrincipal;
Encrypt=yes;
TrustServerCertificate=no;
Connection Timeout=60;
Command Timeout=60;
"""

try:
    print("Attempting connection (60 second timeout)...")
    conn = pyodbc.connect(conn_str)
    print("✅ SUCCESS! Connected to Synapse!")
    
    cursor = conn.cursor()
    cursor.execute("SELECT @@VERSION")
    row = cursor.fetchone()
    print(f"Server version: {row[0][:50]}...")
    
    cursor.close()
    conn.close()
except Exception as e:
    print(f"❌ Failed: {e}")
    print("\nThis might mean:")
    print("1. Synapse is still initializing (can take up to 15 minutes)")
    print("2. Service principal authentication is still propagating")
    print("3. Try again in a few minutes")
