# Troubleshooting Synapse Authentication Error

## Error
```
[28000] [Microsoft][ODBC Driver 17 for SQL Server][SQL Server]Login failed for user '<token-identified principal>'. (18456) (SQLDriverConnect)
```

## This error indicates token-based authentication failure. Here are the common causes and solutions:

## 1. Service Principal Permissions

### Check if Service Principal has correct permissions:
```bash
# Check service principal's role assignments on Synapse workspace
az synapse role assignment list \
  --workspace-name YOUR_SYNAPSE_WORKSPACE \
  --assignee YOUR_SERVICE_PRINCIPAL_CLIENT_ID

# Required roles (at least one):
# - Synapse Administrator
# - Synapse SQL Administrator
# - Synapse Contributor
```

### Grant SQL permissions if missing:
```sql
-- Run this in Synapse Studio as admin
CREATE USER [YOUR_SERVICE_PRINCIPAL_NAME] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [YOUR_SERVICE_PRINCIPAL_NAME];
ALTER ROLE db_datawriter ADD MEMBER [YOUR_SERVICE_PRINCIPAL_NAME];
```

## 2. Connection String Issues

### Correct connection string format for Service Principal:
```python
# Using pyodbc with Service Principal
conn_str = (
    f"DRIVER={{ODBC Driver 18 for SQL Server}};"  # Note: Use 18, not 17
    f"SERVER={workspace_name}-ondemand.sql.azuresynapse.net;"
    f"DATABASE={database_name};"
    f"UID={client_id};"
    f"PWD={client_secret};"
    f"Authentication=ActiveDirectoryServicePrincipal;"  # Critical!
    f"Encrypt=yes;"
    f"TrustServerCertificate=no;"
)
```

### For Managed Identity:
```python
conn_str = (
    f"DRIVER={{ODBC Driver 18 for SQL Server}};"
    f"SERVER={workspace_name}-ondemand.sql.azuresynapse.net;"
    f"DATABASE={database_name};"
    f"Authentication=ActiveDirectoryMsi;"  # For Managed Identity
    f"Encrypt=yes;"
    f"TrustServerCertificate=no;"
)
```

## 3. Token Generation Issues

### If using Azure SDK to get token:
```python
from azure.identity import ClientSecretCredential
import struct
import pyodbc

# Get token
credential = ClientSecretCredential(
    tenant_id=tenant_id,
    client_id=client_id,
    client_secret=client_secret
)

# Get token for Azure SQL/Synapse
token = credential.get_token("https://database.windows.net/.default")

# Convert token to bytes for SQL Server
token_bytes = bytes(token.token, "UTF-8")
exptoken = b''
for i in token_bytes:
    exptoken += bytes({i})
    exptoken += bytes(1)
    
# Use token in connection
conn_str = (
    f"DRIVER={{ODBC Driver 18 for SQL Server}};"
    f"SERVER={workspace_name}-ondemand.sql.azuresynapse.net;"
    f"DATABASE={database_name};"
)

SQL_COPT_SS_ACCESS_TOKEN = 1256
conn = pyodbc.connect(conn_str, attrs_before={SQL_COPT_SS_ACCESS_TOKEN: exptoken})
```

## 4. Database-Level Permissions

### Check if user exists in database:
```sql
-- Run in Synapse Studio
SELECT name, type_desc, authentication_type_desc 
FROM sys.database_principals 
WHERE name = 'YOUR_SERVICE_PRINCIPAL_NAME' 
   OR name = 'YOUR_SERVICE_PRINCIPAL_CLIENT_ID';
```

### Create user if missing:
```sql
-- For Service Principal
CREATE USER [YOUR_SERVICE_PRINCIPAL_NAME] FROM EXTERNAL PROVIDER;

-- Or using client ID
CREATE USER [YOUR_CLIENT_ID] FROM EXTERNAL PROVIDER;

-- Grant permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO [YOUR_SERVICE_PRINCIPAL_NAME];
```

## 5. Azure AD/Entra ID Configuration

### Verify Service Principal exists and is active:
```bash
az ad sp show --id YOUR_CLIENT_ID
```

### Check if Synapse has Azure AD admin configured:
```bash
az synapse workspace show \
  --name YOUR_SYNAPSE_WORKSPACE \
  --resource-group YOUR_RG \
  --query "aadAdmin"
```

## 6. Common Issues Checklist

- [ ] Using ODBC Driver 18 (not 17) for better compatibility
- [ ] Service Principal has Synapse role (Administrator/SQL Administrator)
- [ ] Database user created with `FROM EXTERNAL PROVIDER`
- [ ] Authentication method specified correctly in connection string
- [ ] Client secret is valid and not expired
- [ ] Synapse workspace firewall allows your IP/service
- [ ] Database exists and is accessible
- [ ] Using correct server endpoint (-ondemand for serverless)

## 7. Test Script

```python
#!/usr/bin/env python3
import pyodbc
from azure.identity import ClientSecretCredential

# Configuration
config = {
    'tenant_id': 'YOUR_TENANT_ID',
    'client_id': 'YOUR_CLIENT_ID',
    'client_secret': 'YOUR_CLIENT_SECRET',
    'workspace_name': 'YOUR_SYNAPSE_WORKSPACE',
    'database_name': 'YOUR_DATABASE'
}

# Test 1: Verify credential works
try:
    credential = ClientSecretCredential(
        tenant_id=config['tenant_id'],
        client_id=config['client_id'],
        client_secret=config['client_secret']
    )
    token = credential.get_token("https://database.windows.net/.default")
    print("✅ Token obtained successfully")
except Exception as e:
    print(f"❌ Token generation failed: {e}")
    exit(1)

# Test 2: Try connection with Service Principal auth
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
    cursor.execute("SELECT @@VERSION")
    print("✅ Connection successful!")
    cursor.close()
    conn.close()
except pyodbc.Error as e:
    print(f"❌ Connection failed: {e}")
```

## 8. Resolution Steps

1. **Update ODBC Driver**: Change from Driver 17 to Driver 18
2. **Verify Service Principal**: Ensure it has proper Synapse roles
3. **Create Database User**: Run CREATE USER command in Synapse
4. **Fix Connection String**: Ensure Authentication parameter is set
5. **Test Connection**: Use the test script above

## Most Likely Fix for Your Error

Based on the error, the most likely issue is that the database user hasn't been created. Run this in Synapse Studio:

```sql
-- Replace with your actual service principal name or client ID
CREATE USER [YOUR_SERVICE_PRINCIPAL_NAME] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [YOUR_SERVICE_PRINCIPAL_NAME];
ALTER ROLE db_datawriter ADD MEMBER [YOUR_SERVICE_PRINCIPAL_NAME];
```

Then ensure your connection string includes:
```
Authentication=ActiveDirectoryServicePrincipal
```