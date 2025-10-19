#!/usr/bin/env python3
"""
Synapse Remote Query Client
Executes queries on Azure Synapse Analytics remotely using REST API
"""

import requests
from azure.identity import ClientSecretCredential
import pandas as pd
import time
import json
from datetime import datetime, timedelta

class SynapseAPIClient:
    def __init__(self, tenant_id, client_id, client_secret, workspace_name, database_name='BillingAnalytics'):
        """
        Initialize Synapse API client
        
        Args:
            tenant_id: Azure AD tenant ID
            client_id: Service principal application ID
            client_secret: Service principal secret
            workspace_name: Synapse workspace name
            database_name: Database name (default: BillingAnalytics)
        """
        self.tenant_id = tenant_id
        self.client_id = client_id
        self.client_secret = client_secret
        self.workspace_name = workspace_name
        self.database_name = database_name
        
        # Initialize credential
        self.credential = ClientSecretCredential(
            tenant_id=tenant_id,
            client_id=client_id,
            client_secret=client_secret
        )
        
        # Base URLs
        self.base_url = f"https://{workspace_name}.dev.azuresynapse.net"
        self.sql_endpoint = f"https://{workspace_name}-ondemand.sql.azuresynapse.net"
        
    def _get_headers(self):
        """Get authorization headers for API requests"""
        token = self.credential.get_token("https://dev.azuresynapse.net/.default")
        return {
            'Authorization': f'Bearer {token.token}',
            'Content-Type': 'application/json'
        }
    
    def execute_query_odbc(self, query):
        """
        Execute query using ODBC connection (requires pyodbc)
        This is the most reliable method for serverless SQL pools
        """
        try:
            import pyodbc
        except ImportError:
            print("Please install pyodbc: pip install pyodbc")
            return None
        
        conn_str = (
            f"DRIVER={{ODBC Driver 18 for SQL Server}};"
            f"SERVER={self.workspace_name}-ondemand.sql.azuresynapse.net;"
            f"DATABASE={self.database_name};"
            f"UID={self.client_id};"
            f"PWD={self.client_secret};"
            f"Authentication=ActiveDirectoryServicePrincipal;"
            f"Encrypt=yes;"
            f"TrustServerCertificate=no;"
        )
        
        try:
            conn = pyodbc.connect(conn_str)
            df = pd.read_sql(query, conn)
            conn.close()
            return df
        except Exception as e:
            print(f"Error executing query: {e}")
            return None
    
    def query_billing_summary(self, start_date=None, end_date=None):
        """
        Get billing summary for date range
        
        Args:
            start_date: Start date (YYYY-MM-DD format)
            end_date: End date (YYYY-MM-DD format)
        
        Returns:
            DataFrame with billing summary
        """
        if not start_date:
            start_date = (datetime.now() - timedelta(days=30)).strftime('%Y-%m-%d')
        if not end_date:
            end_date = datetime.now().strftime('%Y-%m-%d')
            
        query = f"""
        SELECT 
            resourceGroupName,
            serviceFamily,
            SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as TotalCostUSD,
            COUNT(*) as TransactionCount,
            COUNT(DISTINCT CAST(date AS DATE)) as DaysActive
        FROM BillingData
        WHERE TRY_CAST(date AS DATE) BETWEEN '{start_date}' AND '{end_date}'
            AND date IS NOT NULL 
            AND date != 'date'
        GROUP BY resourceGroupName, serviceFamily
        ORDER BY TotalCostUSD DESC
        """
        
        return self.execute_query_odbc(query)
    
    def get_daily_costs(self, days_back=30):
        """
        Get daily cost trend
        
        Args:
            days_back: Number of days to look back
        
        Returns:
            DataFrame with daily costs
        """
        query = f"""
        SELECT 
            CAST(date AS DATE) as BillingDate,
            SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as DailyCostUSD,
            COUNT(DISTINCT ResourceId) as ResourceCount,
            COUNT(*) as TransactionCount
        FROM BillingData
        WHERE TRY_CAST(date AS DATE) >= DATEADD(day, -{days_back}, GETDATE())
            AND date IS NOT NULL 
            AND date != 'date'
        GROUP BY CAST(date AS DATE)
        ORDER BY BillingDate DESC
        """
        
        return self.execute_query_odbc(query)
    
    def get_top_resources(self, limit=20):
        """
        Get top resources by cost
        
        Args:
            limit: Number of top resources to return
        
        Returns:
            DataFrame with top resources
        """
        query = f"""
        SELECT TOP {limit}
            ResourceId,
            resourceGroupName,
            serviceFamily,
            SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as TotalCostUSD,
            COUNT(*) as UsageCount
        FROM BillingData
        WHERE ResourceId IS NOT NULL
            AND ResourceId != ''
        GROUP BY ResourceId, resourceGroupName, serviceFamily
        ORDER BY TotalCostUSD DESC
        """
        
        return self.execute_query_odbc(query)
    
    def get_cost_by_location(self):
        """
        Get cost breakdown by Azure region
        
        Returns:
            DataFrame with costs by location
        """
        query = """
        SELECT 
            resourceLocation,
            COUNT(DISTINCT resourceGroupName) as ResourceGroups,
            COUNT(DISTINCT serviceFamily) as Services,
            SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as TotalCostUSD
        FROM BillingData
        WHERE resourceLocation IS NOT NULL
        GROUP BY resourceLocation
        ORDER BY TotalCostUSD DESC
        """
        
        return self.execute_query_odbc(query)
    
    def get_monthly_trend(self):
        """
        Get monthly cost trend
        
        Returns:
            DataFrame with monthly costs
        """
        query = """
        SELECT 
            YEAR(TRY_CAST(date AS DATE)) as Year,
            MONTH(TRY_CAST(date AS DATE)) as Month,
            SUM(TRY_CAST(costInUsd AS DECIMAL(18,6))) as MonthlyCostUSD,
            COUNT(DISTINCT CAST(date AS DATE)) as DaysWithData
        FROM BillingData
        WHERE date IS NOT NULL AND date != 'date'
        GROUP BY YEAR(TRY_CAST(date AS DATE)), MONTH(TRY_CAST(date AS DATE))
        ORDER BY Year DESC, Month DESC
        """
        
        return self.execute_query_odbc(query)


# Example usage
if __name__ == "__main__":
    # Configuration
    config = {
        'tenant_id': 'ba153ff0-3397-4ef5-a214-dd33e8c37bff',
        'client_id': '554b11c1-18f9-46b5-a096-30e0a2cfae6f',
        'client_secret': 'tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams',
        'workspace_name': 'wiv-synapse-billing',
        'database_name': 'BillingAnalytics'
    }
    
    # Initialize client
    client = SynapseAPIClient(**config)
    
    # Example 1: Get daily costs for last 7 days
    print("Daily Costs (Last 7 Days):")
    print("-" * 50)
    daily_costs = client.get_daily_costs(days_back=7)
    if daily_costs is not None:
        print(daily_costs)
    
    # Example 2: Get billing summary
    print("\nBilling Summary:")
    print("-" * 50)
    summary = client.query_billing_summary()
    if summary is not None:
        print(summary.head(10))
    
    # Example 3: Get top resources
    print("\nTop 10 Resources by Cost:")
    print("-" * 50)
    top_resources = client.get_top_resources(limit=10)
    if top_resources is not None:
        print(top_resources)
    
    # Example 4: Get monthly trend
    print("\nMonthly Cost Trend:")
    print("-" * 50)
    monthly = client.get_monthly_trend()
    if monthly is not None:
        print(monthly)