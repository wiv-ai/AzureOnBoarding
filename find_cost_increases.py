#!/usr/bin/env python3
"""
Find subscriptions with >10% cost increase month-over-month
"""

import pyodbc
import pandas as pd
from synapse_config import SYNAPSE_CONFIG as config

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

conn = pyodbc.connect(conn_str)

print('📈 SUBSCRIPTIONS WITH >10% COST INCREASE (July vs August 2025)')
print('='*80)

# Query to compare costs between months
query = '''
WITH MonthlyCosts AS (
    SELECT 
        SubAccountName as Subscription,
        MONTH(TRY_CAST(ChargePeriodStart as DATE)) as Month,
        YEAR(TRY_CAST(ChargePeriodStart as DATE)) as Year,
        SUM(TRY_CAST(EffectiveCost as FLOAT)) as TotalCost
    FROM BillingData
    WHERE SubAccountName IS NOT NULL
        AND SubAccountName != ''
        AND YEAR(TRY_CAST(ChargePeriodStart as DATE)) = 2025
        AND MONTH(TRY_CAST(ChargePeriodStart as DATE)) IN (7, 8)
    GROUP BY 
        SubAccountName,
        MONTH(TRY_CAST(ChargePeriodStart as DATE)),
        YEAR(TRY_CAST(ChargePeriodStart as DATE))
),
Comparison AS (
    SELECT 
        COALESCE(aug.Subscription, jul.Subscription) as Subscription,
        ISNULL(jul.TotalCost, 0) as JulyCost,
        ISNULL(aug.TotalCost, 0) as AugustCost,
        CASE 
            WHEN jul.TotalCost IS NULL OR jul.TotalCost = 0 THEN 
                CASE WHEN aug.TotalCost > 0 THEN 999999 ELSE 0 END
            ELSE 
                ((aug.TotalCost - jul.TotalCost) / jul.TotalCost) * 100
        END as PercentChange,
        aug.TotalCost - ISNULL(jul.TotalCost, 0) as AbsoluteChange
    FROM 
        (SELECT * FROM MonthlyCosts WHERE Month = 8) aug
    FULL OUTER JOIN 
        (SELECT * FROM MonthlyCosts WHERE Month = 7) jul
    ON aug.Subscription = jul.Subscription
)
SELECT 
    Subscription,
    JulyCost,
    AugustCost,
    AbsoluteChange,
    PercentChange
FROM Comparison
WHERE PercentChange > 10
    AND AugustCost > 100  -- Filter out very small subscriptions
ORDER BY PercentChange DESC
'''

try:
    df = pd.read_sql(query, conn)
    
    if not df.empty:
        print("\n📊 Subscriptions with >10% increase from July to August 2025:")
        print("-"*80)
        
        # Format for display
        for idx, row in df.iterrows():
            subscription = row['Subscription'][:40] if row['Subscription'] else 'N/A'
            july = row['JulyCost'] if row['JulyCost'] else 0
            august = row['AugustCost'] if row['AugustCost'] else 0
            change = row['AbsoluteChange'] if row['AbsoluteChange'] else 0
            percent = row['PercentChange'] if row['PercentChange'] else 0
            
            # Special case for new subscriptions
            if percent > 1000:
                print(f"\n🆕 NEW: {subscription}")
                print(f"   July: $0.00 → August: ${august:,.2f}")
                print(f"   New subscription started in August")
            else:
                print(f"\n📈 {subscription}")
                print(f"   July: ${july:,.2f} → August: ${august:,.2f}")
                print(f"   Increase: ${change:,.2f} ({percent:.1f}%)")
        
        print("\n" + "="*80)
        print("📊 SUMMARY:")
        print("-"*80)
        
        # Separate new vs increased
        new_subs = df[df['PercentChange'] > 1000]
        increased_subs = df[(df['PercentChange'] <= 1000) & (df['PercentChange'] > 10)]
        
        print(f"🆕 New subscriptions (started in August): {len(new_subs)}")
        if not new_subs.empty:
            print(f"   Total cost of new subscriptions: ${new_subs['AugustCost'].sum():,.2f}")
        
        print(f"\n📈 Existing subscriptions with >10% increase: {len(increased_subs)}")
        if not increased_subs.empty:
            print(f"   Total July cost: ${increased_subs['JulyCost'].sum():,.2f}")
            print(f"   Total August cost: ${increased_subs['AugustCost'].sum():,.2f}")
            print(f"   Total increase: ${increased_subs['AbsoluteChange'].sum():,.2f}")
            print(f"   Average % increase: {increased_subs['PercentChange'].mean():.1f}%")
        
        # Top 5 by absolute increase
        print("\n💰 Top 5 by absolute cost increase:")
        print("-"*40)
        top5 = df.nlargest(5, 'AbsoluteChange')
        for idx, row in top5.iterrows():
            subscription = row['Subscription'][:35] if row['Subscription'] else 'N/A'
            change = row['AbsoluteChange']
            print(f"   {subscription:<35} +${change:>10,.2f}")
            
    else:
        print("\n✅ No subscriptions found with >10% cost increase")
        
except Exception as e:
    print(f"❌ Error: {str(e)[:200]}")

# Also check for services within subscriptions that increased
print("\n" + "="*80)
print("🔍 DETAILED SERVICE ANALYSIS FOR TOP INCREASING SUBSCRIPTIONS")
print("="*80)

service_query = '''
WITH TopIncreasing AS (
    -- Get top 5 subscriptions by cost increase
    SELECT TOP 5 SubAccountName
    FROM (
        SELECT 
            SubAccountName,
            SUM(CASE WHEN MONTH(TRY_CAST(ChargePeriodStart as DATE)) = 7 
                THEN TRY_CAST(EffectiveCost as FLOAT) ELSE 0 END) as JulyCost,
            SUM(CASE WHEN MONTH(TRY_CAST(ChargePeriodStart as DATE)) = 8 
                THEN TRY_CAST(EffectiveCost as FLOAT) ELSE 0 END) as AugustCost
        FROM BillingData
        WHERE SubAccountName IS NOT NULL
            AND YEAR(TRY_CAST(ChargePeriodStart as DATE)) = 2025
            AND MONTH(TRY_CAST(ChargePeriodStart as DATE)) IN (7, 8)
        GROUP BY SubAccountName
        HAVING SUM(CASE WHEN MONTH(TRY_CAST(ChargePeriodStart as DATE)) = 8 
                   THEN TRY_CAST(EffectiveCost as FLOAT) ELSE 0 END) > 100
    ) t
    WHERE AugustCost > JulyCost * 1.1
    ORDER BY (AugustCost - JulyCost) DESC
)
SELECT 
    SubAccountName as Subscription,
    ServiceName,
    SUM(CASE WHEN MONTH(TRY_CAST(ChargePeriodStart as DATE)) = 7 
        THEN TRY_CAST(EffectiveCost as FLOAT) ELSE 0 END) as JulyCost,
    SUM(CASE WHEN MONTH(TRY_CAST(ChargePeriodStart as DATE)) = 8 
        THEN TRY_CAST(EffectiveCost as FLOAT) ELSE 0 END) as AugustCost,
    SUM(CASE WHEN MONTH(TRY_CAST(ChargePeriodStart as DATE)) = 8 
        THEN TRY_CAST(EffectiveCost as FLOAT) ELSE 0 END) -
    SUM(CASE WHEN MONTH(TRY_CAST(ChargePeriodStart as DATE)) = 7 
        THEN TRY_CAST(EffectiveCost as FLOAT) ELSE 0 END) as Change
FROM BillingData
WHERE SubAccountName IN (SELECT SubAccountName FROM TopIncreasing)
    AND ServiceName IS NOT NULL
    AND YEAR(TRY_CAST(ChargePeriodStart as DATE)) = 2025
    AND MONTH(TRY_CAST(ChargePeriodStart as DATE)) IN (7, 8)
GROUP BY SubAccountName, ServiceName
HAVING SUM(CASE WHEN MONTH(TRY_CAST(ChargePeriodStart as DATE)) = 8 
           THEN TRY_CAST(EffectiveCost as FLOAT) ELSE 0 END) > 
       SUM(CASE WHEN MONTH(TRY_CAST(ChargePeriodStart as DATE)) = 7 
           THEN TRY_CAST(EffectiveCost as FLOAT) ELSE 0 END) * 1.1
ORDER BY Subscription, Change DESC
'''

try:
    df2 = pd.read_sql(service_query, conn)
    
    if not df2.empty:
        print("\n📊 Services with >10% increase within top growing subscriptions:")
        print("-"*80)
        
        current_sub = None
        for idx, row in df2.iterrows():
            if current_sub != row['Subscription']:
                current_sub = row['Subscription']
                print(f"\n🏢 {current_sub}:")
                
            service = row['ServiceName'][:30] if row['ServiceName'] else 'Unknown'
            july = row['JulyCost'] if row['JulyCost'] else 0
            august = row['AugustCost'] if row['AugustCost'] else 0
            change = row['Change'] if row['Change'] else 0
            
            if july > 0:
                percent = ((august - july) / july) * 100
                print(f"   • {service:<30} ${july:>8,.2f} → ${august:>8,.2f} (+{percent:.0f}%)")
            else:
                print(f"   • {service:<30} ${'0.00':>8} → ${august:>8,.2f} (NEW)")
                
except Exception as e:
    print(f"❌ Error in service analysis: {str(e)[:200]}")

conn.close()
print("\n✅ Analysis complete!")