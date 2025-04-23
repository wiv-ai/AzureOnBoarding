#!/bin/bash

# Purpose: This script onboards a new Azure subscription to the Wiv platform by creating an App registration and assigning roles.

# Login to Azure
az login

# Retrieve the current subscription ID and tenant ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "Using Subscription ID: $SUBSCRIPTION_ID"
echo "Using Tenant ID: $TENANT_ID"

# Verify the subscription ID is correct
echo "Fetching list of available subscriptions..."
SUBSCRIPTIONS=$(az account list --query '[].{name:name, id:id}' -o tsv)

if ! echo "$SUBSCRIPTIONS" | grep -q "$SUBSCRIPTION_ID"; then
  echo "The current subscription ID $SUBSCRIPTION_ID is not in the list of available subscriptions. Exiting..."
  echo "Available subscriptions are:"
  echo "$SUBSCRIPTIONS"
  exit 1
fi

# Ensure the subscription is set
az account set --subscription $SUBSCRIPTION_ID

# Input for resource group name
echo "Enter the resource group name:"
read RESOURCE_GROUP

# Ensure the subscription is correctly set before creating the resource group
CURRENT_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
if [ "$CURRENT_SUBSCRIPTION_ID" != "$SUBSCRIPTION_ID" ]; then
  echo "Failed to set the correct subscription before resource group creation. Exiting..."
  exit 1
fi

# Verify or create the resource group
echo "Checking if resource group $RESOURCE_GROUP exists..."
az group show --name $RESOURCE_GROUP &> /dev/null
if [ $? -ne 0 ]; then
  echo "Resource group $RESOURCE_GROUP does not exist. Exiting..."
  exit 1
else
  echo "Resource group $RESOURCE_GROUP exists."
fi

# Fetch the region of the resource group
REGION=$(az group show --name $RESOURCE_GROUP --query location -o tsv)
echo "Using region: $REGION"

# Variables
APP_DISPLAY_NAME="wiv_account"

# Check if the service principal exists and create it if it doesn’t
sp_exists=$(az ad sp list --display-name $APP_DISPLAY_NAME --query "[?appDisplayName=='$APP_DISPLAY_NAME'].{appId:appId}" --output tsv)

if [ -z "$sp_exists" ]; then
    echo "Service principal does not exist. Creating service principal..."
    app_registration=$(az ad app create --display-name $APP_DISPLAY_NAME)
    APP_ID=$(echo $app_registration | jq -r '.appId')
    sp_create_output=$(az ad sp create --id $APP_ID)
else
    echo "Service principal already exists."
    APP_ID=$sp_exists
fi

echo "Service Principal ID: $APP_ID"

# Create new client secret
echo "Creating new client secret..."
if date --version >/dev/null 2>&1; then
    END_DATE=$(date -d "+2 years" +"%Y-%m-%d")
else
    END_DATE=$(date -v +2y +"%Y-%m-%d")
fi
client_secret=$(az ad app credential reset --id $APP_ID --end-date $END_DATE --query password -o tsv)

# Fetch secret value
CLIENT_SECRET_VALUE=$client_secret

# Assign Cost Management Reader role to the app registration
echo "Assigning Cost Management Reader role..."
role_assignment_cost_management=$(az role assignment create --assignee $APP_ID --role "Cost Management Reader" --scope /subscriptions/$SUBSCRIPTION_ID)
if [ $? -ne 0 ]; then
  echo "Failed to assign Cost Management Reader role. Exiting..."
  exit 1
else
  echo "Assigned Cost Management Reader role."
fi

# Assign Monitoring Reader role to the app registration
echo "Assigning Monitoring Reader role..."
role_assignment_monitoring=$(az role assignment create --assignee $APP_ID --role "Monitoring Reader" --scope /subscriptions/$SUBSCRIPTION_ID)
if [ $? -ne 0 ]; then
  echo "Failed to assign Monitoring Reader role. Exiting..."
  exit 1
else
  echo "Assigned Monitoring Reader role."
fi

# Assign Directory Readers role to the app registration
echo "Assigning Directory Readers role..."

# Add Directory.Read.All permission
az ad app permission add --id $APP_ID --api 00000003-0000-0000-c000-000000000000 --api-permissions 7ab1d382-f21e-4acd-a863-ba3e13f7da61=Role

# Grant the permission
az ad app permission grant --id $APP_ID --api 00000003-0000-0000-c000-000000000000 --scope "https://graph.microsoft.com/Directory.Read.All"

# Grant admin consent
echo "Granting admin consent for the application..."
az ad app permission admin-consent --id $APP_ID
if [ $? -eq 0 ]; then
    echo "Admin consent granted successfully."
else
    echo "Failed to grant admin consent. Exiting..."
    exit 1
fi

# Output results
echo "Onboarding script completed. Here are the details:"
echo "Subscription ID: $SUBSCRIPTION_ID"
echo "Application Display Name: $APP_DISPLAY_NAME"
echo "Application (Client) ID: $APP_ID"
echo "Directory (Tenant) ID: $TENANT_ID"
echo "Client Secret Value: $CLIENT_SECRET_VALUE"