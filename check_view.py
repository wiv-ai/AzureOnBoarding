#!/usr/bin/env python3
"""Check if BillingData view exists and create if missing"""

import pyodbc
from azure.identity import ClientSecretCredential
import struct
import sys

# Import configuration
from synapse_config import SYNAPSE_CONFIG, STORAGE_CONFIG

def get_synapse_token():
    """Get Azure AD token for Synapse"""
    credential = ClientSecretCredential(
        tenant_id=SYNAPSE_CONFIG['tenant_id'],
        client_id=SYNAPSE_CONFIG['client_id'],
        client_secret=SYNAPSE_CONFIG['client_secret']
    )
    token = credential.get_token("https://database.windows.net/.default")
    return token.token

def test_connection():
    """Test Synapse connection and check for views"""
    workspace_name = SYNAPSE_CONFIG['workspace_name']
    database_name = SYNAPSE_CONFIG['database_name']
    
    # Get token
    token = get_synapse_token()
    token_bytes = bytes(token, 'utf-8')
    exptoken = b''
    for i in token_bytes:
        exptoken += bytes({i})
        exptoken += bytes(1)
    tokenstruct = struct.pack("=i", len(exptoken)) + exptoken
    
    # Connection string for Synapse serverless SQL pool
    conn_str = (
        f"DRIVER={{ODBC Driver 18 for SQL Server}};"
        f"SERVER={workspace_name}-ondemand.sql.azuresynapse.net;"
        f"DATABASE={database_name};"
        f"Encrypt=yes;"
        f"TrustServerCertificate=no;"
        f"Connection Timeout=30;"
    )
    
    try:
        # Connect
        conn = pyodbc.connect(conn_str, attrs_before={1256: tokenstruct})
        cursor = conn.cursor()
        print(f"✅ Connected to Synapse workspace: {workspace_name}")
        print(f"✅ Using database: {database_name}")
        
        # Check if database exists
        cursor.execute("SELECT DB_NAME() as CurrentDatabase")
        row = cursor.fetchone()
        print(f"✅ Current database: {row.CurrentDatabase}")
        
        # Check for views
        print("\n🔍 Checking for views in database...")
        cursor.execute("""
            SELECT 
                SCHEMA_NAME(schema_id) as SchemaName,
                name as ViewName,
                create_date,
                modify_date
            FROM sys.views
            ORDER BY name
        """)
        
        views = cursor.fetchall()
        if views:
            print(f"✅ Found {len(views)} view(s):")
            for view in views:
                print(f"   - {view.SchemaName}.{view.ViewName} (created: {view.create_date})")
        else:
            print("❌ No views found in database")
            print("\n📝 Creating BillingData view...")
            
            # Create the view
            storage_account = STORAGE_CONFIG['storage_account']
            container = STORAGE_CONFIG['container']
            export_path = STORAGE_CONFIG['export_path']
            
            create_view_sql = f"""
            CREATE VIEW BillingData AS
            SELECT *
            FROM OPENROWSET(
                BULK 'https://{storage_account}.blob.core.windows.net/{container}/{export_path}/*/*.csv',
                FORMAT = 'CSV',
                PARSER_VERSION = '2.0',
                HEADER_ROW = TRUE
            ) AS BillingExport
            """
            
            try:
                cursor.execute(create_view_sql)
                conn.commit()
                print("✅ BillingData view created successfully!")
            except Exception as e:
                print(f"❌ Error creating view: {e}")
                
                # Try with abfss protocol
                print("\n📝 Trying with abfss:// protocol (Managed Identity)...")
                create_view_sql_abfss = f"""
                CREATE VIEW BillingData AS
                SELECT *
                FROM OPENROWSET(
                    BULK 'abfss://{container}@{storage_account}.dfs.core.windows.net/{export_path}/*/*.csv',
                    FORMAT = 'CSV',
                    PARSER_VERSION = '2.0',
                    HEADER_ROW = TRUE
                ) AS BillingExport
                """
                
                try:
                    cursor.execute(create_view_sql_abfss)
                    conn.commit()
                    print("✅ BillingData view created with Managed Identity!")
                except Exception as e2:
                    print(f"❌ Error with abfss: {e2}")
        
        # Test the view
        print("\n🔍 Testing BillingData view...")
        try:
            cursor.execute("SELECT TOP 1 * FROM BillingData")
            print("✅ BillingData view is working!")
        except Exception as e:
            print(f"❌ View exists but query failed: {e}")
            
        cursor.close()
        conn.close()
        
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False
    
    return True

if __name__ == "__main__":
    print("🔍 Checking Synapse views...\n")
    if test_connection():
        print("\n✅ Synapse is ready!")
    else:
        print("\n❌ Please check the configuration")
        sys.exit(1)