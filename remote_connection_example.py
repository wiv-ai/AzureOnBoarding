
import pyodbc
import pandas as pd

# Connection string
conn_str = (
    f"DRIVER={ODBC Driver 18 for SQL Server};"
    f"SERVER=wiv-synapse-billing-ondemand.sql.azuresynapse.net;"
    f"DATABASE=master;"
    f"UID=554b11c1-18f9-46b5-a096-30e0a2cfae6f;"
    f"PWD=tmC8Q~xjjkGx9MD2mPY5OeUh.HcbeqlReT6C7ams;"
    f"Authentication=ActiveDirectoryServicePrincipal;"
    f"Encrypt=yes;"
    f"TrustServerCertificate=no;"
)

# Connect and execute query
try:
    conn = pyodbc.connect(conn_str)
    query = '''
    SELECT TOP 10 * 
    FROM OPENROWSET(
        BULK 'https://billingstorage77626.blob.core.windows.net/billing-exports/billing-data/DailyBillingExport/20250801-20250831/DailyBillingExport_6440a15d-9fef-4a3b-9dc9-4b2e07e2372d.csv',
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
    '''
    
    df = pd.read_sql(query, conn)
    print(df)
    conn.close()
    
except Exception as e:
    print(f"Error: {e}")
