#!/usr/bin/env python3
"""
Test billing queries with FOCUS format compatibility
Maps the actual Azure billing export columns to FOCUS standard names
"""

import pyodbc
import pandas as pd
import sys

# Load configuration
try:
    from synapse_config import SYNAPSE_CONFIG as config
except ImportError:
    print("Error: synapse_config.py not found. Please create it with your credentials.")
    print("See synapse_config.example.py for the required format.")
    sys.exit(1)

print("="*70)
print("📊 TESTING BILLING DATA QUERIES WITH FOCUS FORMAT")
print("="*70)

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
    
    # First, get the actual column names
    print("\n📋 Checking BillingData view columns...")
    cursor.execute("SELECT TOP 1 * FROM BillingData")
    columns = [desc[0] for desc in cursor.description]
    
    print(f"Found {len(columns)} columns")
    
    # Column mapping from Azure billing export to FOCUS-like names
    # Azure Export columns -> FOCUS standard names
    column_mapping = {
        'date': 'ChargePeriodStart',
        'costInUsd': 'EffectiveCost',
        'costInBillingCurrency': 'BilledCost',
        'consumedService': 'ServiceName',
        'serviceFamily': 'ServiceCategory',
        'subscriptionName': 'SubAccountName',
        'SubscriptionId': 'SubAccountId',
        'resourceGroupName': 'ResourceGroup',
        'resourceLocation': 'Region',
        'ResourceId': 'ResourceId',
        'meterCategory': 'MeterCategory',
        'meterSubCategory': 'MeterSubCategory',
        'meterName': 'MeterName',
        'quantity': 'ConsumedQuantity',
        'unitOfMeasure': 'ConsumedUnit',
        'chargeType': 'ChargeType',
        'billingCurrency': 'BillingCurrency',
        'tags': 'Tags'
    }
    
    print("\n📊 Column Mapping (Azure Export → FOCUS):")
    for azure_col, focus_col in list(column_mapping.items())[:5]:
        if azure_col in columns:
            print(f"  ✅ {azure_col} → {focus_col}")
        else:
            print(f"  ❌ {azure_col} not found")
    
    # Test Query 1: Daily Costs (Last 7 Days)
    print("\n" + "="*70)
    print("Query 1: Daily Costs (Last 7 Days)")
    print("-"*70)
    
    daily_query = """
    SELECT 
        CAST(date as DATE) as BillingDate,
        SUM(TRY_CAST(costInUsd AS FLOAT)) as DailyCostUSD,
        COUNT(DISTINCT ResourceId) as ResourceCount,
        COUNT(*) as TransactionCount
    FROM BillingData
    WHERE date >= DATEADD(day, -7, GETDATE())
        AND date IS NOT NULL 
    GROUP BY CAST(date as DATE)
    ORDER BY BillingDate DESC
    """
    
    try:
        df = pd.read_sql(daily_query, conn)
        print("\n✅ Daily costs query successful!")
        print(df.to_string())
    except Exception as e:
        print(f"❌ Error: {str(e)[:200]}")
    
    # Test Query 2: Service Costs Summary
    print("\n" + "="*70)
    print("Query 2: Service Costs Summary (Top 10)")
    print("-"*70)
    
    service_query = """
    SELECT TOP 10
        consumedService as ServiceName,
        serviceFamily as ServiceCategory,
        SUM(TRY_CAST(costInUsd AS FLOAT)) as TotalCostUSD,
        COUNT(*) as TransactionCount
    FROM BillingData
    WHERE date >= DATEADD(day, -30, GETDATE())
        AND consumedService IS NOT NULL
    GROUP BY consumedService, serviceFamily
    ORDER BY TotalCostUSD DESC
    """
    
    try:
        df = pd.read_sql(service_query, conn)
        print("\n✅ Service costs query successful!")
        print(df.to_string())
    except Exception as e:
        print(f"❌ Error: {str(e)[:200]}")
    
    # Test Query 3: Monthly Cost Trend
    print("\n" + "="*70)
    print("Query 3: Monthly Cost Trend")
    print("-"*70)
    
    monthly_query = """
    SELECT 
        YEAR(TRY_CAST(date as DATE)) as Year,
        MONTH(TRY_CAST(date as DATE)) as Month,
        SUM(TRY_CAST(costInUsd AS FLOAT)) as MonthlyTotalUSD,
        SUM(TRY_CAST(costInBillingCurrency AS FLOAT)) as MonthlyBilledCurrency,
        COUNT(*) as Transactions
    FROM BillingData
    WHERE date IS NOT NULL
    GROUP BY 
        YEAR(TRY_CAST(date as DATE)),
        MONTH(TRY_CAST(date as DATE))
    ORDER BY Year DESC, Month DESC
    """
    
    try:
        df = pd.read_sql(monthly_query, conn)
        print("\n✅ Monthly trend query successful!")
        print(df.to_string())
    except Exception as e:
        print(f"❌ Error: {str(e)[:200]}")
    
    # Test Query 4: Cost per Subscription
    print("\n" + "="*70)
    print("Query 4: Cost per Subscription (Top 20)")
    print("-"*70)
    
    subscription_query = """
    SELECT TOP 20
        subscriptionName as SubAccountName,
        SubscriptionId as SubAccountId,
        SUM(TRY_CAST(costInUsd as FLOAT)) as TotalCostUSD,
        SUM(TRY_CAST(costInBillingCurrency as FLOAT)) as BilledCost,
        COUNT(*) as Transactions,
        COUNT(DISTINCT consumedService) as UniqueServices
    FROM BillingData
    WHERE subscriptionName IS NOT NULL
        AND subscriptionName != ''
    GROUP BY subscriptionName, SubscriptionId
    ORDER BY TotalCostUSD DESC
    """
    
    try:
        df = pd.read_sql(subscription_query, conn)
        print("\n✅ Subscription costs query successful!")
        print("\n📊 Top Subscriptions by Cost:")
        print("-"*70)
        
        for _, row in df.iterrows():
            print(f"Subscription: {row['SubAccountName']}")
            print(f"  ID: {row['SubAccountId']}")
            print(f"  Total Cost (USD): ${row['TotalCostUSD']:.2f}")
            print(f"  Transactions: {row['Transactions']}")
            print(f"  Unique Services: {row['UniqueServices']}")
            print()
    except Exception as e:
        print(f"❌ Error: {str(e)[:200]}")
    
    # Test Query 5: Resource Group Costs
    print("\n" + "="*70)
    print("Query 5: Resource Group Costs (Top 10)")
    print("-"*70)
    
    rg_query = """
    SELECT TOP 10
        resourceGroupName as ResourceGroup,
        SUM(TRY_CAST(costInUsd AS FLOAT)) as TotalCostUSD,
        COUNT(DISTINCT ResourceId) as ResourceCount,
        COUNT(DISTINCT consumedService) as ServiceCount
    FROM BillingData
    WHERE resourceGroupName IS NOT NULL
        AND resourceGroupName != ''
    GROUP BY resourceGroupName
    ORDER BY TotalCostUSD DESC
    """
    
    try:
        df = pd.read_sql(rg_query, conn)
        print("\n✅ Resource group costs query successful!")
        print(df.to_string())
    except Exception as e:
        print(f"❌ Error: {str(e)[:200]}")
    
    # Create a FOCUS-compatible view for future use
    print("\n" + "="*70)
    print("Creating FOCUS-Compatible View")
    print("-"*70)
    
    focus_view_sql = """
    CREATE OR ALTER VIEW BillingDataFOCUS AS
    SELECT 
        -- FOCUS Standard Columns
        date as ChargePeriodStart,
        date as ChargePeriodEnd,
        costInUsd as EffectiveCost,
        costInBillingCurrency as BilledCost,
        consumedService as ServiceName,
        serviceFamily as ServiceCategory,
        subscriptionName as SubAccountName,
        SubscriptionId as SubAccountId,
        resourceGroupName as ResourceGroup,
        resourceLocation as Region,
        ResourceId as ResourceId,
        meterCategory as MeterCategory,
        meterSubCategory as MeterSubCategory,
        meterName as MeterName,
        quantity as ConsumedQuantity,
        unitOfMeasure as ConsumedUnit,
        chargeType as ChargeType,
        billingCurrency as BillingCurrency,
        tags as Tags,
        
        -- Keep original columns too
        *
    FROM BillingData
    """
    
    try:
        cursor.execute(focus_view_sql)
        print("\n✅ Created BillingDataFOCUS view with FOCUS-compatible column names!")
        print("   You can now use FOCUS standard column names in queries:")
        print("   - ChargePeriodStart (date)")
        print("   - EffectiveCost (costInUsd)")
        print("   - ServiceName (consumedService)")
        print("   - SubAccountName (subscriptionName)")
    except Exception as e:
        if "already exists" in str(e):
            print("\n✅ BillingDataFOCUS view already exists")
        else:
            print(f"\n⚠️ Could not create FOCUS view: {str(e)[:100]}")
    
    cursor.close()
    conn.close()
    
    print("\n" + "="*70)
    print("✅ All billing query tests completed!")
    print("="*70)
    
    print("\n📝 Summary:")
    print("  - BillingData view uses Azure billing export column names")
    print("  - BillingDataFOCUS view provides FOCUS-compatible column names")
    print("  - Both views can be used for querying billing data")
    print("\n💡 Tips:")
    print("  - Use 'date' for charge period")
    print("  - Use 'costInUsd' for effective cost in USD")
    print("  - Use 'costInBillingCurrency' for billed cost")
    print("  - Use 'subscriptionName' for customer/account grouping")
    
except pyodbc.Error as e:
    print(f"\n❌ Connection failed: {e}")
    print("\nPlease check:")
    print("1. synapse_config.py exists with correct credentials")
    print("2. BillingData view has been created")
    print("3. Service principal has proper permissions")
except Exception as e:
    print(f"\n❌ Unexpected error: {e}")