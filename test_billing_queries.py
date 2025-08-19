#!/usr/bin/env python3
"""
Test billing queries with correct FOCUS column names
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
print("📊 TESTING BILLING DATA QUERIES")
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
    print("\n📋 Getting column names from BillingData view...")
    cursor.execute("SELECT TOP 1 * FROM BillingData")
    columns = [desc[0] for desc in cursor.description]
    
    print(f"Found {len(columns)} columns\n")
    
    # Find relevant columns for our queries
    date_cols = [c for c in columns if 'date' in c.lower() or 'period' in c.lower()]
    cost_cols = [c for c in columns if 'cost' in c.lower()]
    service_cols = [c for c in columns if 'service' in c.lower()]
    resource_cols = [c for c in columns if 'resource' in c.lower()]
    
    print("📊 Relevant columns found:")
    print(f"  Date columns: {date_cols[:5]}")
    print(f"  Cost columns: {cost_cols[:5]}")
    print(f"  Service columns: {service_cols[:5]}")
    print(f"  Resource columns: {resource_cols[:5]}")
    
    # Test Query 1: Daily costs (last 7 days)
    print("\n" + "="*70)
    print("Query 1: Daily Costs (Last 7 Days)")
    print("-"*70)
    
    daily_query = """
    SELECT 
        CAST(ChargePeriodStart as DATE) as BillingDate,
        SUM(TRY_CAST(EffectiveCost AS FLOAT)) as DailyCostUSD,
        COUNT(DISTINCT ResourceId) as ResourceCount,
        COUNT(*) as TransactionCount
    FROM BillingData
    WHERE ChargePeriodStart >= DATEADD(day, -7, GETDATE())
        AND ChargePeriodStart IS NOT NULL 
    GROUP BY CAST(ChargePeriodStart as DATE)
    ORDER BY BillingDate DESC
    """
    
    try:
        df = pd.read_sql(daily_query, conn)
        print("\n✅ Daily costs query successful!")
        print(df.to_string())
    except Exception as e:
        print(f"❌ Error: {str(e)[:200]}")
    
    # Test Query 2: Service costs summary
    print("\n" + "="*70)
    print("Query 2: Service Costs Summary")
    print("-"*70)
    
    service_query = """
    SELECT TOP 10
        ServiceName,
        ServiceCategory,
        SUM(TRY_CAST(EffectiveCost AS FLOAT)) as TotalCostUSD,
        COUNT(*) as TransactionCount
    FROM BillingData
    WHERE ChargePeriodStart >= DATEADD(day, -30, GETDATE())
        AND ServiceName IS NOT NULL
    GROUP BY ServiceName, ServiceCategory
    ORDER BY TotalCostUSD DESC
    """
    
    try:
        df = pd.read_sql(service_query, conn)
        print("\n✅ Service costs query successful!")
        print(df.to_string())
    except Exception as e:
        print(f"❌ Error: {str(e)[:200]}")
    
    # Test Query 3: Monthly trend
    print("\n" + "="*70)
    print("Query 3: Monthly Cost Trend")
    print("-"*70)
    
    monthly_query = """
    SELECT 
        YEAR(TRY_CAST(ChargePeriodStart as DATE)) as Year,
        MONTH(TRY_CAST(ChargePeriodStart as DATE)) as Month,
        SUM(TRY_CAST(EffectiveCost AS FLOAT)) as MonthlyTotal,
        SUM(TRY_CAST(BilledCost AS FLOAT)) as BilledTotal,
        COUNT(*) as Transactions
    FROM BillingData
    WHERE ChargePeriodStart IS NOT NULL
    GROUP BY 
        YEAR(TRY_CAST(ChargePeriodStart as DATE)),
        MONTH(TRY_CAST(ChargePeriodStart as DATE))
    ORDER BY Year, Month
    """
    
    try:
        df = pd.read_sql(monthly_query, conn)
        print("\n✅ Monthly trend query successful!")
        print(df.to_string())
    except Exception as e:
        print(f"❌ Error: {str(e)[:200]}")
    
    # Test Query 4: Using the MonthlyCosts view
    print("\n" + "="*70)
    print("Query 4: Top Services from MonthlyCosts View")
    print("-"*70)
    
    view_query = """
    SELECT TOP 10 
        ServiceName,
        SUM(TotalCost) as TotalCost,
        SUM(TransactionCount) as Transactions
    FROM MonthlyCosts
    GROUP BY ServiceName
    ORDER BY TotalCost DESC
    """
    
    try:
        df = pd.read_sql(view_query, conn)
        print("\n✅ MonthlyCosts view query successful!")
        print(df.to_string())
    except Exception as e:
        print(f"❌ Error: {str(e)[:200]}")
    
    cursor.close()
    conn.close()
    
    print("\n" + "="*70)
    print("✅ All test queries completed!")
    print("="*70)
    print("\n📝 Summary:")
    print("  - BillingData view has FOCUS format columns")
    print("  - Use ChargePeriodStart/ChargePeriodEnd for dates")
    print("  - Use EffectiveCost, BilledCost for cost data")
    print("  - Use ServiceName, ServiceCategory for service info")
    print("  - MonthlyCosts view provides pre-aggregated data")
    
except Exception as e:
    print(f"❌ Connection failed: {e}")