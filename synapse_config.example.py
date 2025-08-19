"""
Example Synapse configuration file
Copy this to synapse_config.py and fill in your actual values

IMPORTANT: 
- Never commit synapse_config.py to git (it's in .gitignore)
- Keep your credentials secure
"""

SYNAPSE_CONFIG = {
    'tenant_id': 'YOUR_TENANT_ID',
    'client_id': 'YOUR_SERVICE_PRINCIPAL_CLIENT_ID',
    'client_secret': 'YOUR_SERVICE_PRINCIPAL_CLIENT_SECRET',
    'workspace_name': 'YOUR_SYNAPSE_WORKSPACE_NAME',
    'database_name': 'BillingAnalytics'  # or your database name
}

# Optional: Storage configuration (can also be set as environment variables)
STORAGE_CONFIG = {
    'storage_account': 'YOUR_STORAGE_ACCOUNT_NAME',
    'container': 'YOUR_CONTAINER_NAME',
    'subscription_id': 'YOUR_SUBSCRIPTION_ID'
}