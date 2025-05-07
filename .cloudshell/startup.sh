#!/bin/bash

echo ""
echo "🚀 Azure Onboarding Script Starting..."
echo "--------------------------------------"

# Login to Azure (if needed)
# az login

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

# Get Tenant ID
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Tenant ID: $TENANT_ID"

# Create client secret
echo ""
echo "🔑 Creating client secret..."
if date --version >/dev/null 2>&1; then
    END_DATE=$(date -d "+2 years" +"%Y-%m-%d")
else
    END_DATE=$(date -v +2y +"%Y-%m-%d")
fi
CLIENT_SECRET=$(az ad app credential reset --id "$APP_ID" --end-date "$END_DATE" --query password -o tsv)

# Assign roles to all subscriptions
echo ""
echo "🔒 Assigning roles to all subscriptions..."
SUBSCRIPTIONS=$(az account list --query '[].id' -o tsv)

for SUBSCRIPTION_ID in $SUBSCRIPTIONS; do
  echo "Processing subscription: $SUBSCRIPTION_ID"

  # Assign Cost Management Reader role
  echo "  - Assigning Cost Management Reader..."
  az role assignment create --assignee "$APP_ID" --role "Cost Management Reader" --scope "/subscriptions/$SUBSCRIPTION_ID"

  # Assign Monitoring Reader role
  echo "  - Assigning Monitoring Reader..."
  az role assignment create --assignee "$APP_ID" --role "Monitoring Reader" --scope "/subscriptions/$SUBSCRIPTION_ID"

  echo "  ✅ Done with subscription: $SUBSCRIPTION_ID"
done

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
echo "✅ Multi-Subscription Role Assignment Complete"
echo "--------------------------------------"
echo "📄 Tenant ID:           $TENANT_ID"
echo "📄 App (Client) ID:     $APP_ID"
echo "📄 Client Secret:       $CLIENT_SECRET"
echo "📄 Assigned Roles:      Cost Management Reader, Monitoring Reader"
echo "📄 Scope:               All subscriptions"