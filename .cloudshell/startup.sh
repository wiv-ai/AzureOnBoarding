#!/bin/bash

echo ""
echo "🚀 Azure Onboarding Script Starting..."
echo "--------------------------------------"

# Login to Azure (if needed)
# az login

# Fetch and list all subscriptions
SUBSCRIPTIONS=$(az account list --query '[].{name:name, id:id}' -o tsv)

echo "📦 Available Azure subscriptions:"
echo "Name      ID"
echo "--------  ------------------------------------"
echo "$SUBSCRIPTIONS"

# Prompt user to pick subscription
read -p "🔹 Enter the Subscription ID to use: " SUBSCRIPTION_ID
az account set --subscription "$SUBSCRIPTION_ID"

TENANT_ID=$(az account show --query tenantId -o tsv)

echo ""
echo "✅ Now using Subscription ID: $SUBSCRIPTION_ID"
echo "Tenant ID: $TENANT_ID"

# List resource groups
echo ""
echo "📁 Fetching resource groups in this subscription..."
RG_LIST=$(az group list --query "[].name" -o tsv)
echo "$RG_LIST"

read -p "🔹 Enter the Resource Group to use: " RESOURCE_GROUP
echo "🔍 Checking if resource group '$RESOURCE_GROUP' exists..."
az group show --name "$RESOURCE_GROUP" &>/dev/null

if [ $? -ne 0 ]; then
  echo "❌ Resource group '$RESOURCE_GROUP' does not exist. Exiting..."
  exit 1
fi

REGION=$(az group show --name "$RESOURCE_GROUP" --query location -o tsv)
echo "🌍 Using region: $REGION"

# App registration and service principal
APP_DISPLAY_NAME="wiv_account"
echo ""
echo "🔐 Checking for service principal '$APP_DISPLAY_NAME'..."
APP_ID=$(az ad sp list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv)

if [ -z "$APP_ID" ]; then
  echo "🔧 Creating new App Registration..."
  APP_ID=$(az ad app create --display-name "$APP_DISPLAY_NAME" --query appId -o tsv)
  az ad sp create --id "$APP_ID" > /dev/null
else
  echo "✅ Service principal exists. App ID: $APP_ID"
fi

# Create client secret
echo ""
echo "🔑 Creating client secret..."
if date --version >/dev/null 2>&1; then
    END_DATE=$(date -d "+2 years" +"%Y-%m-%d")
else
    END_DATE=$(date -v +2y +"%Y-%m-%d")
fi
CLIENT_SECRET=$(az ad app credential reset --id "$APP_ID" --end-date "$END_DATE" --query password -o tsv)

# Assign roles
echo ""
echo "🔒 Assigning roles..."
az role assignment create --assignee "$APP_ID" --role "Cost Management Reader" --scope "/subscriptions/$SUBSCRIPTION_ID"
az role assignment create --assignee "$APP_ID" --role "Monitoring Reader" --scope "/subscriptions/$SUBSCRIPTION_ID"

# Optional: Microsoft Graph permissions
echo ""
read -p "Do you want to grant Microsoft Graph permissions (e.g., Directory.Read.All)? (y/n): " GRANT_PERMS

if [[ "$GRANT_PERMS" =~ ^[Yy]$ ]]; then
    echo "📘 Granting Microsoft Graph permissions..."

    echo "🔹 Adding Directory.Read.All permission..."
    az ad app permission add \
        --id "$APP_ID" \
        --api 00000003-0000-0000-c000-000000000000 \
        --api-permissions 7ab1d382-f21e-4acd-a863-ba3e13f7da61=Role

    echo "🔹 Granting the permission..."
    az ad app permission grant \
        --id "$APP_ID" \
        --api 00000003-0000-0000-c000-000000000000 \
        --scope "https://graph.microsoft.com/Directory.Read.All"

    echo "🔹 Requesting admin consent..."
    az ad app permission admin-consent --id "$APP_ID"
    if [ $? -eq 0 ]; then
        echo "✅ Admin consent granted successfully."
    else
        echo "⚠️  Admin consent failed. You may need to manually grant consent via Azure Portal."
    fi
else
    echo "🚫 Skipping Microsoft Graph permission grant."
fi

# Final output
echo ""
echo "✅ Onboarding Complete"
echo "--------------------------------------"
echo "📄 Subscription ID:     $SUBSCRIPTION_ID"
echo "📄 Tenant ID:           $TENANT_ID"
echo "📄 Resource Group:      $RESOURCE_GROUP"
echo "📄 Region:              $REGION"
echo "📄 App Display Name:    $APP_DISPLAY_NAME"
echo "📄 App (Client) ID:     $APP_ID"
echo "📄 Client Secret:       $CLIENT_SECRET"