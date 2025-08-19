#!/usr/bin/env python3
"""
Create billing views in Synapse using the actual storage configuration
"""

import pyodbc
import sys
from synapse_config import SYNAPSE_CONFIG as config

# Your actual storage configuration
STORAGE_ACCOUNT = "wivcostexports"
CONTAINER = "costexport"
EXPORT_PATH = "daily/wiv-focus-cost"

def execute_sql_commands(sql_commands):
    """Execute SQL commands on Synapse"""
    conn_str = (
        f"DRIVER={{ODBC Driver 18 for SQL Server}};"
        f"SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;"
        f"DATABASE={config['database_name']};"
        f"UID={config['client_id']};"
        f"PWD={config['client_secret']};"
        f"Authentication=ActiveDirectoryServicePrincipal;"
        f"Encrypt=yes;"
        f"TrustServerCertificate=no;"
    )
    
    try:
        print(f"🔌 Connecting to Synapse workspace: {config['workspace_name']}")
        conn = pyodbc.connect(conn_str)
        cursor = conn.cursor()
        print("✅ Connected successfully\n")
        
        # Execute each command separately
        for sql_command in sql_commands:
            if not sql_command.strip():
                continue
                
            # Show what we're executing (first 150 chars)
            cmd_preview = sql_command.strip()[:150].replace('\n', ' ')
            print(f"📝 Executing: {cmd_preview}...")
            
            try:
                cursor.execute(sql_command)
                conn.commit()
                print("   ✅ Success\n")
            except pyodbc.Error as e:
                error_msg = str(e)
                if "already exists" in error_msg.lower():
                    print(f"   ⚠️  Already exists (skipping)\n")
                else:
                    print(f"   ❌ Error: {error_msg}\n")
                    # Continue with other commands even if one fails
        
        cursor.close()
        conn.close()
        return True
        
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False

print("="*60)
print("🚀 Creating Billing Views in Synapse")
print("="*60)
print(f"Storage Account: {STORAGE_ACCOUNT}")
print(f"Container: {CONTAINER}")
print(f"Export Path: {EXPORT_PATH}")
print(f"Full Path: https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/")
print("="*60 + "\n")

# SQL commands to create the billing views
sql_commands = [
    # Drop existing views if they exist
    """
    IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingData')
        DROP VIEW BillingData
    """,
    
    """
    IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingDataCSP')
        DROP VIEW BillingDataCSP
    """,
    
    """
    IF EXISTS (SELECT * FROM sys.views WHERE name = 'BillingDataFOCUS')
        DROP VIEW BillingDataFOCUS
    """,
    
    # Create main BillingData view for standard format
    f"""
    CREATE VIEW BillingData AS
    SELECT *
    FROM OPENROWSET(
        BULK 'https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        HEADER_ROW = TRUE
    ) AS BillingExport
    """,
    
    # Create FOCUS format view (since your path mentions "focus-cost")
    f"""
    CREATE VIEW BillingDataFOCUS AS
    SELECT 
        BillingAccountId,
        BillingAccountName,
        BillingPeriodStartDate,
        BillingPeriodEndDate,
        ServiceCategory,
        ServiceName,
        ServiceSubcategory,
        ResourceId,
        ResourceName,
        ResourceType,
        Region,
        Zone,
        UsageQuantity,
        UsageUnit,
        PricingCategory,
        PricingQuantity,
        PricingUnit,
        BilledCost,
        EffectiveCost,
        AmortizedCost,
        ContractedCost,
        ListCost,
        BillingCurrency,
        Tags,
        InvoiceId,
        ChargeCategory,
        ChargeFrequency,
        ChargeDescription,
        ChargePeriodStart,
        ChargePeriodEnd,
        CommitmentDiscountCategory,
        CommitmentDiscountName,
        CommitmentDiscountType,
        Provider,
        PublisherName,
        PublisherType,
        SkuId,
        SkuName,
        SubAccountId,
        SubAccountName,
        x_AccountOwnerId,
        x_AccountOwnerName,
        x_BilledCostInUsd,
        x_EffectiveCostInUsd,
        x_OnDemandCostInUsd,
        x_SkuDetails,
        x_SkuIsCreditEligible,
        x_SkuMeterCategory,
        x_SkuMeterSubcategory,
        x_SkuMeterId,
        x_SkuMeterName,
        x_SkuOfferId,
        x_SkuOrderId,
        x_SkuPartNumber,
        x_SkuProductId,
        x_SkuProductName,
        x_SkuServiceFamily,
        x_SkuServiceName,
        x_SkuTerm,
        x_SkuTier
    FROM OPENROWSET(
        BULK 'https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        HEADER_ROW = TRUE
    ) 
    WITH (
        BillingAccountId NVARCHAR(200),
        BillingAccountName NVARCHAR(500),
        BillingPeriodStartDate DATE,
        BillingPeriodEndDate DATE,
        ServiceCategory NVARCHAR(200),
        ServiceName NVARCHAR(200),
        ServiceSubcategory NVARCHAR(200),
        ResourceId NVARCHAR(1000),
        ResourceName NVARCHAR(500),
        ResourceType NVARCHAR(200),
        Region NVARCHAR(100),
        Zone NVARCHAR(100),
        UsageQuantity DECIMAL(28,10),
        UsageUnit NVARCHAR(100),
        PricingCategory NVARCHAR(200),
        PricingQuantity DECIMAL(28,10),
        PricingUnit NVARCHAR(100),
        BilledCost DECIMAL(28,10),
        EffectiveCost DECIMAL(28,10),
        AmortizedCost DECIMAL(28,10),
        ContractedCost DECIMAL(28,10),
        ListCost DECIMAL(28,10),
        BillingCurrency NVARCHAR(10),
        Tags NVARCHAR(MAX),
        InvoiceId NVARCHAR(200),
        ChargeCategory NVARCHAR(100),
        ChargeFrequency NVARCHAR(100),
        ChargeDescription NVARCHAR(500),
        ChargePeriodStart DATE,
        ChargePeriodEnd DATE,
        CommitmentDiscountCategory NVARCHAR(200),
        CommitmentDiscountName NVARCHAR(500),
        CommitmentDiscountType NVARCHAR(100),
        Provider NVARCHAR(200),
        PublisherName NVARCHAR(500),
        PublisherType NVARCHAR(100),
        SkuId NVARCHAR(200),
        SkuName NVARCHAR(500),
        SubAccountId NVARCHAR(200),
        SubAccountName NVARCHAR(500),
        x_AccountOwnerId NVARCHAR(200),
        x_AccountOwnerName NVARCHAR(500),
        x_BilledCostInUsd DECIMAL(28,10),
        x_EffectiveCostInUsd DECIMAL(28,10),
        x_OnDemandCostInUsd DECIMAL(28,10),
        x_SkuDetails NVARCHAR(MAX),
        x_SkuIsCreditEligible NVARCHAR(10),
        x_SkuMeterCategory NVARCHAR(200),
        x_SkuMeterSubcategory NVARCHAR(200),
        x_SkuMeterId NVARCHAR(200),
        x_SkuMeterName NVARCHAR(500),
        x_SkuOfferId NVARCHAR(200),
        x_SkuOrderId NVARCHAR(200),
        x_SkuPartNumber NVARCHAR(200),
        x_SkuProductId NVARCHAR(200),
        x_SkuProductName NVARCHAR(500),
        x_SkuServiceFamily NVARCHAR(200),
        x_SkuServiceName NVARCHAR(200),
        x_SkuTerm NVARCHAR(100),
        x_SkuTier NVARCHAR(100)
    ) AS FOCUSData
    """,
    
    # Create a simplified daily costs view
    f"""
    CREATE VIEW DailyCosts AS
    SELECT 
        CAST(ChargePeriodStart as DATE) as Date,
        ServiceCategory,
        ServiceName,
        SUM(EffectiveCost) as TotalCost,
        BillingCurrency,
        COUNT(*) as TransactionCount
    FROM OPENROWSET(
        BULK 'https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/*.csv',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0',
        HEADER_ROW = TRUE
    ) 
    WITH (
        ChargePeriodStart DATE,
        ServiceCategory NVARCHAR(200),
        ServiceName NVARCHAR(200),
        EffectiveCost DECIMAL(28,10),
        BillingCurrency NVARCHAR(10)
    ) AS DailyData
    GROUP BY CAST(ChargePeriodStart as DATE), ServiceCategory, ServiceName, BillingCurrency
    """
]

# Execute the SQL commands
if execute_sql_commands(sql_commands):
    print("\n" + "="*60)
    print("✅ Billing views created successfully!")
    print("="*60)
    
    # Now test if we can query the views
    print("\n🔍 Testing the views...")
    
    test_sql = """
    SELECT TOP 5 
        ChargePeriodStart,
        ServiceName,
        EffectiveCost,
        BillingCurrency
    FROM BillingDataFOCUS
    ORDER BY ChargePeriodStart DESC
    """
    
    conn_str = (
        f"DRIVER={{ODBC Driver 18 for SQL Server}};"
        f"SERVER={config['workspace_name']}-ondemand.sql.azuresynapse.net;"
        f"DATABASE={config['database_name']};"
        f"UID={config['client_id']};"
        f"PWD={config['client_secret']};"
        f"Authentication=ActiveDirectoryServicePrincipal;"
        f"Encrypt=yes;"
        f"TrustServerCertificate=no;"
    )
    
    try:
        conn = pyodbc.connect(conn_str)
        cursor = conn.cursor()
        
        print("\n📊 Sample data from BillingDataFOCUS view:")
        print("-" * 60)
        
        try:
            cursor.execute(test_sql)
            rows = cursor.fetchall()
            
            if rows:
                print(f"{'Date':<12} {'Service':<30} {'Cost':<15} {'Currency':<10}")
                print("-" * 60)
                for row in rows:
                    date_str = str(row[0])[:10] if row[0] else 'N/A'
                    service = str(row[1])[:28] if row[1] else 'N/A'
                    cost = f"{float(row[2] or 0):.2f}"
                    currency = str(row[3]) if row[3] else 'N/A'
                    print(f"{date_str:<12} {service:<30} {cost:<15} {currency:<10}")
            else:
                print("No data found. The billing export might not have run yet.")
                print("It typically takes 5-30 minutes after setup for the first export.")
                
        except pyodbc.Error as e:
            print(f"Could not query view: {e}")
            print("\nThis might mean:")
            print("1. The CSV files don't exist yet in the storage path")
            print("2. The column names in the CSV don't match the FOCUS format")
            print("3. Service principal doesn't have access to the storage account")
            
        cursor.close()
        conn.close()
        
    except Exception as e:
        print(f"Test query failed: {e}")
    
    print("\n" + "="*60)
    print("📋 Available Views:")
    print("  - BillingData: Raw billing data (all columns)")
    print("  - BillingDataFOCUS: FOCUS format with typed columns")
    print("  - DailyCosts: Aggregated daily costs by service")
    print("\n🔗 Storage Path:")
    print(f"  https://{STORAGE_ACCOUNT}.blob.core.windows.net/{CONTAINER}/{EXPORT_PATH}/")
    print("\n📝 Next Steps:")
    print("1. Ensure the service principal has 'Storage Blob Data Reader' role on the storage account")
    print("2. Wait for billing export to run if no data is available yet")
    print("3. Query the views using SQL or the Python client")
    
else:
    print("\n❌ Failed to create some views. Check the errors above.")