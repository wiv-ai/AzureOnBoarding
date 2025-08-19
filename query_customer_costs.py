#!/usr/bin/env python3
"""
Query costs per customer subscription
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

print('📊 COST PER CUSTOMER SUBSCRIPTION')
print('='*70)

# Query costs grouped by subscription/account
query = '''
SELECT 
    SubAccountName as CustomerSubscription,
    SubAccountId as SubscriptionId,
    SUM(TRY_CAST(EffectiveCost as FLOAT)) as TotalCost,
    SUM(TRY_CAST(BilledCost as FLOAT)) as BilledCost,
    COUNT(*) as Transactions,
    COUNT(DISTINCT ServiceName) as UniqueServices
FROM BillingData
WHERE SubAccountName IS NOT NULL
    AND SubAccountName != ''
GROUP BY SubAccountName, SubAccountId
ORDER BY TotalCost DESC
'''

try:
    df = pd.read_sql(query, conn)
    
    if not df.empty:
        print("\nCosts by Customer Subscription:")
        print("-"*70)
        
        # Format the dataframe for better display
        df['TotalCost'] = df['TotalCost'].apply(lambda x: f"${x:,.2f}" if pd.notna(x) else "$0.00")
        df['BilledCost'] = df['BilledCost'].apply(lambda x: f"${x:,.2f}" if pd.notna(x) else "$0.00")
        
        print(df.to_string(index=False))
        
        print('\n📊 SUMMARY')
        print('-'*70)
        print(f'Total Customer Subscriptions: {len(df)}')
    else:
        print("No SubAccount data found. Trying BillingAccount...")
        
except Exception as e:
    print(f'SubAccount columns not found: {str(e)[:100]}')
    print('\nTrying BillingAccount columns instead...\n')
    
# Try with BillingAccount columns instead
query2 = '''
SELECT 
    BillingAccountName as CustomerAccount,
    BillingAccountId as AccountId,
    SUM(TRY_CAST(EffectiveCost as FLOAT)) as TotalCost,
    SUM(TRY_CAST(BilledCost as FLOAT)) as BilledCost,
    COUNT(*) as Transactions,
    COUNT(DISTINCT ServiceName) as UniqueServices
FROM BillingData
WHERE BillingAccountName IS NOT NULL
    AND BillingAccountName != ''
GROUP BY BillingAccountName, BillingAccountId
ORDER BY TotalCost DESC
'''

try:
    df2 = pd.read_sql(query2, conn)
    
    if not df2.empty:
        print("Costs by Billing Account:")
        print("-"*70)
        
        # Format the dataframe for better display
        df2['TotalCost'] = df2['TotalCost'].apply(lambda x: f"${x:,.2f}" if pd.notna(x) else "$0.00")
        df2['BilledCost'] = df2['BilledCost'].apply(lambda x: f"${x:,.2f}" if pd.notna(x) else "$0.00")
        
        print(df2.to_string(index=False))
        
        print('\n📊 SUMMARY')
        print('-'*70)
        print(f'Total Billing Accounts: {len(df2)}')
        
except Exception as e2:
    print(f'Error with BillingAccount: {str(e2)[:100]}')

# Also try to get unique subscription information from other fields
print('\n📊 ADDITIONAL SUBSCRIPTION ANALYSIS')
print('='*70)

query3 = '''
SELECT 
    x_AccountOwnerName as AccountOwner,
    x_AccountOwnerId as OwnerId,
    SUM(TRY_CAST(EffectiveCost as FLOAT)) as TotalCost,
    COUNT(*) as Transactions
FROM BillingData
WHERE x_AccountOwnerName IS NOT NULL
    AND x_AccountOwnerName != ''
GROUP BY x_AccountOwnerName, x_AccountOwnerId
ORDER BY TotalCost DESC
'''

try:
    df3 = pd.read_sql(query3, conn)
    
    if not df3.empty:
        print("Costs by Account Owner:")
        print("-"*70)
        
        df3['TotalCost'] = df3['TotalCost'].apply(lambda x: f"${x:,.2f}" if pd.notna(x) else "$0.00")
        
        print(df3.to_string(index=False))
        
except Exception as e3:
    print(f'No account owner data found: {str(e3)[:100]}')

conn.close()
print('\n✅ Analysis complete!')