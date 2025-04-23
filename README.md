# Azure Wiv Platform Onboarding Script

## Overview
This bash script automates the process of onboarding a new Azure subscription to the Wiv platform. It creates an App registration in Azure Active Directory and assigns the necessary roles for the Wiv platform to monitor and manage your Azure resources.

## Prerequisites
- Azure CLI installed and configured on your system
- Active Azure subscription
- Permissions to create App registrations and assign roles
- An existing resource group in your Azure subscription
- `jq` command-line JSON processor

## Features
- Creates a new service principal (App registration) for Wiv platform
- Assigns required Azure roles:
    - Cost Management Reader
    - Monitoring Reader
    - Directory Readers (via Graph API permissions)
- Generates and secures client credentials
- Validates subscription and resource group before proceeding

## Usage

1. Download the script:
   ```
   curl -O https://path/to/AzureWivOnBoarding.sh
   ```

2. Make the script executable:
   ```
   chmod +x AzureWivOnBoarding.sh
   ```

3. Run the script:
   ```
   ./AzureWivOnBoarding.sh
   ```

4. Follow the prompts:
    - The script will log you into Azure
    - You'll be asked to specify a resource group
    - The script will validate your inputs before proceeding

5. After successful execution, the script will output:
    - Subscription ID
    - Application (Client) ID
    - Directory (Tenant) ID
    - Client Secret Value

## Output Details
Upon successful completion, the script provides the following credentials that you'll need to configure Wiv platform:

- **Subscription ID**: Your Azure subscription identifier
- **Application Display Name**: "wiv_account"
- **Application (Client) ID**: The ID of the created App registration
- **Directory (Tenant) ID**: Your Azure AD tenant ID
- **Client Secret Value**: The generated client secret (save this immediately as it cannot be retrieved later)

## Security Considerations
- The client secret is generated with a 2-year expiration date
- The script assigns only the minimum required permissions
- Store the output credentials securely
- Consider rotating the client secret periodically

## Troubleshooting
- If the script fails to set the correct subscription, verify your Azure CLI configuration
- If role assignment fails, ensure you have sufficient permissions in your Azure subscription
- For permission grant failures, ensure you have Global Administrator or Application Administrator role in your Azure AD

## Notes
- The script checks if a service principal with the same name already exists to prevent duplicates
- Directory permission assignments require admin consent, which is automatically requested

