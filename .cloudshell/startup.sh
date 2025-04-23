#!/bin/bash
set -euo pipefail

echo ""
echo "🚀 Azure Onboarding Script Starting..."
echo "--------------------------------------"

# 📌 List all subscriptions
echo "📦 Available Azure subscriptions:"
az account list --query "[].{Name:name, ID:id}" -o table

read -p "🔹 Enter the Subscription ID to use: " SUBSCRIPTION_ID

# Set the selected subscription
az account set --subscription "$SUBSCRIPTION_ID"

# Confirm subscription switch
echo ""
echo "✅ Now using Subscription ID: $(az account show --query id -o tsv)"
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Tenant ID: $TENANT_ID"

# 📌 List resource groups in the selected subscription
echo ""
echo "📁 Fetching resource groups in this subscription..."
az group list --query "[].name" -o table

read -p "🔹 Enter the Resource Group to use: " RESOURCE_GROUP

if [ -z "$RESOURCE_GROUP" ]; then
  echo "❌ No resource group selected. Exiting..."
  exit 1
fi

# Check if RG exists
echo "🔍 Checking if resource group '$RESOURCE_GROUP' exists..."
if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
  echo "❌ Resource group '$RESOURCE_GROUP' does not exist. Exiting..."
  exit 1
fi

REGION=$(az group show --name "$RESOURCE_GROUP" --query location -o tsv)
echo "🌍 Using region: $REGION"

# ✅ Proceed with app registration, SP creation, and roles

APP_DISPLAY_NAME="wiv_account"
echo ""
echo "🔐 Checking for service principal '$APP_DISPLAY_NAME'..."
APP_ID=$(az ad sp list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv || echo "")

if [ -z "$APP_ID" ]; then
  echo "Creating new app registration and service principal..."
  APP_ID=$(az ad app create --display-name "$APP_DISPLAY_NAME" --query appId -o tsv)
  az ad sp create --id "$APP_ID"
else
  echo "✅ Service principal exists. App ID: $APP_ID"
fi

# 🔑 Create a client secret
echo ""
echo "🔑 Creating client secret..."
if date --version >/dev/null 2>&1; then
  END_DATE=$(date -d "+2 years" +"%Y-%m-%d")
else
  END_DATE=$(date -v +2y +"%Y-%m-%d")
fi

CLIENT_SECRET_VALUE=$(az ad app credential reset --id "$APP_ID" --end-date "$END_DATE" --query password -o tsv)

# 🎯 Role Assignments
echo "🔒 Assigning roles..."
az role assignment create --assignee "$APP_ID" --role "Cost Management Reader" --scope "/subscriptions/$SUBSCRIPTION_ID"
az role assignment create --assignee "$APP_ID" --role "Monitoring Reader" --scope "/subscriptions/$SUBSCRIPTION_ID"

# 📘 Graph Permissions
echo "📘 Granting Microsoft Graph permissions..."
az ad app permission add --id "$APP_ID" \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 7ab1d382-f21e-4acd-a863-ba3e13f7da61=Role

az ad app permission grant --id "$APP_ID" \
  --api 00000003-0000-0000-c000-000000000000 \
  --scope "https://graph.microsoft.com/Directory.Read.All"

az ad app permission admin-consent --id "$APP_ID"

# ✅ Output results
echo ""
echo "🎉 Onboarding complete!"
echo "Subscription ID: $SUBSCRIPTION_ID"
echo "Tenant ID:       $TENANT_ID"
echo "App Display Name: $APP_DISPLAY_NAME"
echo "App (Client) ID: $APP_ID"
echo "Client Secret:   $CLIENT_SECRET_VALUE"