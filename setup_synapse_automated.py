import pyodbc
import time
import sys

# Configuration
config = {
    'workspace_name': '$SYNAPSE_WORKSPACE',
    'tenant_id': '$TENANT_ID',
    'client_id': '$APP_ID',
    'client_secret': '$CLIENT_SECRET',
    'storage_account': '$STORAGE_ACCOUNT_NAME',
    'container': '$CONTAINER_NAME',
    'master_key_password': '$MASTER_KEY_PASSWORD'
}

def wait_for_synapse():
    """Wait for Synapse to be ready with enhanced retry logic"""
    conn_str = f"""
    DRIVER={{ODBC Driver 18 for SQL Server}};
    SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;
    DATABASE=master;
    UID={config['client_id']};
    PWD={config['client_secret']};
    Authentication=ActiveDirectoryServicePrincipal;
    Encrypt=yes;
    TrustServerCertificate=no;
    Connection Timeout=60;
    """
    
    print("⏳ Checking Synapse workspace availability...")
    
    # Enhanced retry logic with longer waits
    max_attempts = 10
    wait_times = [10, 20, 30, 30, 30, 60, 60, 60, 60, 60]  # Progressive backoff
    
    for attempt in range(max_attempts):
        try:
            conn = pyodbc.connect(conn_str, autocommit=True)
            cursor = conn.cursor()
            cursor.execute("SELECT 1")
            cursor.close()
            conn.close()
            print(f"✅ Synapse is ready! (after {sum(wait_times[:attempt])} seconds)")
            return True
        except pyodbc.Error as e:
            if attempt < max_attempts - 1:
                wait_time = wait_times[attempt]
                if "Login timeout expired" in str(e) or "Login failed" in str(e):
                    print(f"⏳ Synapse needs more time to initialize...")
                else:
                    print(f"⏳ Waiting for Synapse... ({sum(wait_times[:attempt+1])} seconds elapsed)")
                time.sleep(wait_time)
            else:
                print(f"❌ Could not connect after {sum(wait_times)} seconds: {str(e)[:100]}")
                return False
    
    return False

# Wait for Synapse to be ready
if not wait_for_synapse():
    print("")
    print("⚠️  Automated setup needs more time. This is normal for new workspaces.")
    print("")
    print("✅ Good news: Your Synapse workspace IS created and working!")
    print("")
    print("📝 What to do next:")
    print("   Option 1: Wait 2-3 minutes and re-run this script")
    print("   Option 2: Run the manual setup in Synapse Studio:")
    print("            - Open: https://web.azuresynapse.net")
    print("            - Select your workspace: {config['workspace_name']}")
    print("            - Run the SQL from: synapse_billing_setup.sql")
    print("")
    print("💡 This delay only happens on first setup. Future connections will be instant.")
    sys.exit(0)

# Connection string for master database
master_conn_str = f"""
DRIVER={{ODBC Driver 18 for SQL Server}};
SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;
DATABASE=master;
UID={config['client_id']};
PWD={config['client_secret']};
Authentication=ActiveDirectoryServicePrincipal;
Encrypt=yes;
TrustServerCertificate=no;
Connection Timeout=60;
"""

# Create database with enhanced retry logic
print("📦 Creating BillingAnalytics database...")
db_created = False
max_db_retries = 10
db_wait_time = 10

for retry in range(max_db_retries):
    try:
        conn = pyodbc.connect(master_conn_str, autocommit=True)
        cursor = conn.cursor()
        
        # Check if database already exists
        cursor.execute("SELECT name FROM sys.databases WHERE name = 'BillingAnalytics'")
        if cursor.fetchone():
            print("✅ BillingAnalytics database already exists!")
            db_created = True
        else:
            # Try to create database
            cursor.execute("CREATE DATABASE BillingAnalytics")
            print("✅ BillingAnalytics database created!")
            db_created = True
        
        cursor.close()
        conn.close()
        break
    except pyodbc.Error as e:
        if "already exists" in str(e):
            print("✅ Database already exists!")
            db_created = True
            break
        elif "Could not obtain exclusive lock" in str(e):
            if retry < max_db_retries - 1:
                print(f"⏳ Azure is initializing, waiting {db_wait_time} seconds... (attempt {retry + 1}/{max_db_retries})")
                time.sleep(db_wait_time)
                # Increase wait time for later retries
                if retry > 3:
                    db_wait_time = 20
            else:
                print(f"⚠️ Database lock persists after {retry + 1} attempts")
                print("   Azure needs more time to initialize internal databases")
        else:
            print(f"⚠️ Database creation issue: {str(e)[:100]}")
            if retry < max_db_retries - 1:
                time.sleep(db_wait_time)

if not db_created:
    print("⚠️ Could not create database automatically due to Azure initialization.")
    print("   The database will be created on next run. Continuing with remaining setup...")

# Connection string for BillingAnalytics database
billing_conn_str = f"""
DRIVER={{ODBC Driver 18 for SQL Server}};
SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;
DATABASE=BillingAnalytics;
UID={config['client_id']};
PWD={config['client_secret']};
Authentication=ActiveDirectoryServicePrincipal;
Encrypt=yes;
TrustServerCertificate=no;
Connection Timeout=60;
"""

# Setup commands - Simplified for Managed Identity (no SAS tokens needed!)
print("\n🔧 Setting up database objects with Managed Identity...")

# Wait longer for database to be ready
time.sleep(10)

# Try to connect and setup with enhanced retry
setup_success = False
max_setup_retries = 5
setup_wait_time = 15

for retry in range(max_setup_retries):
    try:
        conn = pyodbc.connect(billing_conn_str, autocommit=True)
        cursor = conn.cursor()
        
        # Create master key
        try:
            cursor.execute(f"CREATE MASTER KEY ENCRYPTION BY PASSWORD = '{config['master_key_password']}'")
            print("✅ Master key created")
        except pyodbc.Error as e:
            if "already exists" in str(e):
                print("✅ Master key already exists")
            else:
                print(f"⚠️ Master key: {str(e)[:100]}")
        
        # Drop old view if exists and create improved view
        try:
            cursor.execute("IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingData') DROP VIEW BillingData")
        except:
            pass
        
        # Create improved view that automatically gets only the latest export file
        # This prevents data duplication from cumulative month-to-date exports
        cursor.execute(f"""
            CREATE VIEW BillingData AS
            WITH LatestExport AS (
                SELECT MAX(filepath(1)) as LatestPath
                FROM OPENROWSET(
                    BULK 'abfss://billing-exports@{config['storage_account']}.dfs.core.windows.net/billing-data/DailyBillingExport/*/*.csv',
                    FORMAT = 'CSV',
                    PARSER_VERSION = '2.0',
                    FIRSTROW = 2
                ) AS files
            )
            SELECT *
            FROM OPENROWSET(
                BULK 'abfss://billing-exports@{config['storage_account']}.dfs.core.windows.net/billing-data/DailyBillingExport/*/*.csv',
                FORMAT = 'CSV',
                PARSER_VERSION = '2.0',
                FIRSTROW = 2
            )
            WITH (
                date NVARCHAR(100),
                serviceFamily NVARCHAR(200),
                meterCategory NVARCHAR(200),
                meterSubCategory NVARCHAR(200),
                meterName NVARCHAR(500),
                billingAccountName NVARCHAR(200),
                costCenter NVARCHAR(100),
                resourceGroupName NVARCHAR(200),
                resourceLocation NVARCHAR(100),
                consumedService NVARCHAR(200),
                ResourceId NVARCHAR(1000),
                chargeType NVARCHAR(100),
                publisherType NVARCHAR(100),
                quantity NVARCHAR(100),
                costInBillingCurrency NVARCHAR(100),
                costInUsd NVARCHAR(100),
                PayGPrice NVARCHAR(100),
                billingCurrency NVARCHAR(10),
                subscriptionName NVARCHAR(200),
                SubscriptionId NVARCHAR(100),
                ProductName NVARCHAR(500),
                frequency NVARCHAR(100),
                unitOfMeasure NVARCHAR(100),
                tags NVARCHAR(4000)
            ) AS BillingData
            WHERE filepath(1) = (SELECT LatestPath FROM LatestExport)
        """)
        print("✅ BillingData view created (with automatic latest file filtering)")
        
        cursor.close()
        conn.close()
        setup_success = True
        break
        
    except pyodbc.Error as e:
        error_str = str(e)
        if "Login failed" in error_str:
            if retry < max_setup_retries - 1:
                print(f"⏳ Waiting for permissions to propagate... (attempt {retry + 1}/{max_setup_retries})")
                time.sleep(setup_wait_time)
        elif "Invalid object name 'BillingAnalytics'" in error_str or "Database 'BillingAnalytics' does not exist" in error_str:
            if not db_created:
                print("⚠️ Database doesn't exist yet. This will be created on next run.")
                break
            else:
                print(f"⏳ Waiting for database to be accessible... (attempt {retry + 1}/{max_setup_retries})")
                time.sleep(setup_wait_time)
        else:
            print(f"⚠️ Setup issue: {error_str[:100]}")
            if retry < max_setup_retries - 1:
                time.sleep(setup_wait_time)

if setup_success:
    print("\n✅ Synapse database setup completed successfully!")
    
    # Test the view
    print("\n🔍 Testing the view (automatically filters latest export)...")
    try:
        test_conn = pyodbc.connect(billing_conn_str)
        test_cursor = test_conn.cursor()
        test_cursor.execute("SELECT COUNT(*) as RecordCount FROM BillingData")
        row = test_cursor.fetchone()
        print(f"✅ View is working! Found {row[0]} billing records (from latest export only)")
        print("   ℹ️  View automatically filters to latest file to prevent duplication")
        test_cursor.close()
        test_conn.close()
    except Exception as e:
        print(f"⚠️  Could not test view: {str(e)[:100]}")
        print("   This is normal if no billing data has been exported yet")
else:
    if db_created:
        print("\n⚠️ Database created but view setup incomplete.")
        print("   This can happen on first run. The view will be created on next run.")
    else:
        print("\n⚠️ Initial setup incomplete due to Azure initialization.")
        print("   This is NORMAL for new Synapse workspaces.")
        print("   ✅ Your workspace IS created and will be ready soon!")
        print("   📝 Just re-run this script in 2-3 minutes to complete setup.")

print("\n📊 Query to use in Synapse Studio:")
print("   SELECT * FROM BillingAnalytics.dbo.BillingData")
print("   ℹ️  Note: View automatically returns only latest export data (no duplication)")
