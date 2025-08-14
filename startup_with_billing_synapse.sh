#!/bin/bash

echo ""
echo "🚀 Azure Onboarding Script with Billing & Synapse Starting..."
echo "--------------------------------------"

# Login to Azure (if needed)
# az login

# Fetch and list all subscriptions
SUBSCRIPTIONS=$(az account list --query '[].{name:name, id:id}' -o tsv)

echo "📦 Available Azure subscriptions:"
echo "Name      ID"
echo "--------  ------------------------------------"
echo "$SUBSCRIPTIONS"

# Prompt user to pick subscription for creating the app
read -p "🔹 Enter the Subscription ID to use for creating the application: " APP_SUBSCRIPTION_ID
az account set --subscription "$APP_SUBSCRIPTION_ID"

# Get Tenant ID
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Tenant ID: $TENANT_ID"

# App registration and service principal
APP_DISPLAY_NAME="wiv_account"
echo ""
echo "🔐 Checking for service principal '$APP_DISPLAY_NAME'..."
APP_ID=$(az ad sp list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv)

if [ -z "$APP_ID" ]; then
  echo "🔧 Creating new App Registration..."
  APP_ID=$(az ad app create --display-name "$APP_DISPLAY_NAME" --query appId -o tsv)
  az ad sp create --id "$APP_ID" > /dev/null
  echo "✅ Service principal created. App ID: $APP_ID"
  
  # Create client secret for new app
  echo ""
  echo "🔑 Creating client secret..."
  if date --version >/dev/null 2>&1; then
      END_DATE=$(date -d "+2 years" +"%Y-%m-%d")
  else
      END_DATE=$(date -v +2y +"%Y-%m-%d")
  fi
  CLIENT_SECRET=$(az ad app credential reset --id "$APP_ID" --end-date "$END_DATE" --query password -o tsv)
  echo "✅ Client secret created successfully"
else
  echo "✅ Service principal already exists. App ID: $APP_ID"
  echo "⏭️  Skipping app creation and client secret generation..."
  CLIENT_SECRET="<EXISTING_CLIENT_SECRET_REQUIRED>"
  echo "ℹ️  Note: You'll need to manually update the client secret in generated scripts for remote access."
fi

# Assign roles to all subscriptions
echo ""
echo "🔒 Do you want to assign roles to all subscriptions or only specific ones? (all/specific): "
read SCOPE_CHOICE

if [[ "$SCOPE_CHOICE" =~ ^[Aa]ll$ ]]; then
  echo "🔒 Assigning roles to all subscriptions..."
  SUBSCRIPTIONS_TO_PROCESS=$(az account list --query '[].id' -o tsv)
else
  echo "🔒 Enter comma-separated list of subscription IDs to assign roles to (or press Enter to use the same subscription): "
  read SPECIFIC_SUBSCRIPTIONS

  if [ -z "$SPECIFIC_SUBSCRIPTIONS" ]; then
    SUBSCRIPTIONS_TO_PROCESS="$APP_SUBSCRIPTION_ID"
  else
    SUBSCRIPTIONS_TO_PROCESS=$(echo $SPECIFIC_SUBSCRIPTIONS | tr ',' ' ')
  fi
fi

for SUBSCRIPTION_ID in $SUBSCRIPTIONS_TO_PROCESS; do
  echo "Processing subscription: $SUBSCRIPTION_ID"

  # Assign Cost Management Reader role
  echo "  - Assigning Cost Management Reader..."
  az role assignment create --assignee "$APP_ID" --role "Cost Management Reader" --scope "/subscriptions/$SUBSCRIPTION_ID" --only-show-errors

  # Assign Monitoring Reader role
  echo "  - Assigning Monitoring Reader..."
  az role assignment create --assignee "$APP_ID" --role "Monitoring Reader" --scope "/subscriptions/$SUBSCRIPTION_ID" --only-show-errors

  # Assign Storage Blob Data Contributor role for billing exports
  echo "  - Assigning Storage Blob Data Contributor..."
  az role assignment create --assignee "$APP_ID" --role "Storage Blob Data Contributor" --scope "/subscriptions/$SUBSCRIPTION_ID" --only-show-errors

  # Assign Contributor role for Synapse workspace management
  echo "  - Assigning Contributor role for Synapse management..."
  az role assignment create --assignee "$APP_ID" --role "Contributor" --scope "/subscriptions/$SUBSCRIPTION_ID" --only-show-errors

  echo "  ✅ Done with subscription: $SUBSCRIPTION_ID"
done

# ===========================
# BILLING EXPORT CONFIGURATION
# ===========================
echo ""
echo "💰 Configuring Azure Cost Management Billing Export..."
echo "--------------------------------------"

# Prompt for resource group
read -p "🔹 Enter Resource Group name for billing resources (or press Enter for 'rg-billing-export'): " BILLING_RG
BILLING_RG=${BILLING_RG:-"rg-billing-export"}

# Check if resource group exists and get its location
echo "📁 Checking resource group '$BILLING_RG'..."
RG_EXISTS=$(az group exists --name "$BILLING_RG")

if [ "$RG_EXISTS" = "true" ]; then
    # Resource group exists, get its location
    AZURE_REGION=$(az group show --name "$BILLING_RG" --query location -o tsv)
    echo "✅ Using existing resource group in region: $AZURE_REGION"
else
    # Resource group doesn't exist, ask for region
    echo "🌍 Resource group doesn't exist. Select Azure region for new resources:"
    echo "   1. East US 2 (eastus2)"
    echo "   2. West US 2 (westus2)"
    echo "   3. Central US (centralus)"
    echo "   4. North Europe (northeurope)"
    echo "   5. West Europe (westeurope)"
    read -p "Enter your choice (1-5) or press Enter for default (eastus2): " REGION_CHOICE

    case $REGION_CHOICE in
        1|"") AZURE_REGION="eastus2" ;;
        2) AZURE_REGION="westus2" ;;
        3) AZURE_REGION="centralus" ;;
        4) AZURE_REGION="northeurope" ;;
        5) AZURE_REGION="westeurope" ;;
        *) AZURE_REGION="eastus2" ;;
    esac

    echo "📍 Creating resource group in region: $AZURE_REGION"
    az group create --name "$BILLING_RG" --location "$AZURE_REGION" --only-show-errors
fi

# Create storage account for billing exports
STORAGE_ACCOUNT_NAME="billingstorage$(date +%s | tail -c 6)"
echo "📦 Creating storage account '$STORAGE_ACCOUNT_NAME'..."
az storage account create \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$BILLING_RG" \
    --location "$AZURE_REGION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --only-show-errors

# Create container for billing exports
CONTAINER_NAME="billing-exports"
echo "📂 Creating container '$CONTAINER_NAME'..."
STORAGE_KEY=$(az storage account keys list \
    --resource-group "$BILLING_RG" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --query '[0].value' -o tsv)

az storage container create \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --account-key "$STORAGE_KEY" \
    --only-show-errors

# Create daily billing export
EXPORT_NAME="DailyBillingExport"
echo "📊 Creating daily billing export '$EXPORT_NAME'..."

# Get storage account resource ID
STORAGE_RESOURCE_ID=$(az storage account show \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$BILLING_RG" \
    --query id -o tsv)

# Create the export using REST API (as CLI doesn't have direct support)
az rest --method PUT \
    --uri "https://management.azure.com/subscriptions/$APP_SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/$EXPORT_NAME?api-version=2021-10-01" \
    --body @- <<EOF
{
  "properties": {
    "schedule": {
      "status": "Active",
      "recurrence": "Daily",
      "recurrencePeriod": {
        "from": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "to": "$(date -u -d '+5 years' +%Y-%m-%dT%H:%M:%SZ)"
      }
    },
    "format": "Csv",
    "deliveryInfo": {
      "destination": {
        "resourceId": "$STORAGE_RESOURCE_ID",
        "container": "$CONTAINER_NAME",
        "rootFolderPath": "billing-data"
      }
    },
    "definition": {
      "type": "ActualCost",
      "timeframe": "MonthToDate",
      "dataSet": {
        "granularity": "Daily",
        "configuration": {
          "columns": [
            "Date",
            "ServiceFamily",
            "MeterCategory",
            "MeterSubcategory",
            "MeterName",
            "BillingAccountName",
            "CostCenter",
            "ResourceGroup",
            "ResourceLocation",
            "ConsumedService",
            "ResourceId",
            "ChargeType",
            "PublisherType",
            "Quantity",
            "CostInBillingCurrency",
            "CostInUSD",
            "PayGPrice",
            "BillingCurrencyCode",
            "SubscriptionName",
            "SubscriptionId",
            "ProductName",
            "Frequency",
            "UnitOfMeasure",
            "Tags"
          ]
        }
      }
    }
  }
}
EOF

echo "✅ Daily billing export configured successfully"

# ===========================
# SYNAPSE WORKSPACE SETUP
# ===========================
echo ""
echo "🔷 Setting up Azure Synapse Analytics Workspace..."
echo "--------------------------------------"

# Prompt for Synapse workspace name
read -p "🔹 Enter Synapse workspace name (or press Enter for 'wiv-synapse-billing'): " SYNAPSE_WORKSPACE
SYNAPSE_WORKSPACE=${SYNAPSE_WORKSPACE:-"wiv-synapse-billing"}

# Create Synapse workspace
echo "🏗️ Creating Synapse workspace '$SYNAPSE_WORKSPACE'..."

# Create Data Lake Storage Gen2 for Synapse
SYNAPSE_STORAGE="synapsedl$(date +%s | tail -c 6)"
echo "📦 Creating Data Lake Storage Gen2 account '$SYNAPSE_STORAGE'..."
az storage account create \
    --name "$SYNAPSE_STORAGE" \
    --resource-group "$BILLING_RG" \
    --location "$AZURE_REGION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --hierarchical-namespace true \
    --only-show-errors

# Create filesystem for Synapse
FILESYSTEM_NAME="synapsefilesystem"
echo "📂 Creating filesystem '$FILESYSTEM_NAME'..."
az storage fs create \
    --name "$FILESYSTEM_NAME" \
    --account-name "$SYNAPSE_STORAGE" \
    --auth-mode login \
    --only-show-errors

# Create Synapse workspace
echo "🔧 Creating Synapse workspace..."
SQL_ADMIN_USER="sqladminuser"
SQL_ADMIN_PASSWORD="P@ssw0rd$(date +%s | tail -c 6)!"

az synapse workspace create \
    --name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --storage-account "$SYNAPSE_STORAGE" \
    --file-system "$FILESYSTEM_NAME" \
    --sql-admin-login-user "$SQL_ADMIN_USER" \
    --sql-admin-login-password "$SQL_ADMIN_PASSWORD" \
    --location "$AZURE_REGION" \
    --only-show-errors

# Wait for workspace to be created
echo "⏳ Waiting for Synapse workspace to be fully provisioned..."
az synapse workspace wait --resource-group "$BILLING_RG" --workspace-name "$SYNAPSE_WORKSPACE" --created

# Create firewall rule to allow Azure services
echo "🔥 Configuring firewall rules..."
az synapse workspace firewall-rule create \
    --name "AllowAllAzureServices" \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --start-ip-address "0.0.0.0" \
    --end-ip-address "0.0.0.0" \
    --only-show-errors

# Create firewall rule to allow all IPs (for remote access)
echo "🌐 Creating firewall rule for remote access..."
az synapse workspace firewall-rule create \
    --name "AllowAllIPs" \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --start-ip-address "0.0.0.0" \
    --end-ip-address "255.255.255.255" \
    --only-show-errors

# ===========================
# SYNAPSE PERMISSIONS SETUP
# ===========================
echo ""
echo "🔐 Configuring Synapse permissions for wiv_account..."
echo "--------------------------------------"

# Get Synapse workspace resource ID
SYNAPSE_RESOURCE_ID=$(az synapse workspace show \
    --name "$SYNAPSE_WORKSPACE" \
    --resource-group "$BILLING_RG" \
    --query id -o tsv)

# Assign Synapse Administrator role to the service principal
echo "👤 Assigning Synapse Administrator role..."
az synapse role assignment create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --role "Synapse Administrator" \
    --assignee "$APP_ID" \
    --only-show-errors

# Assign Synapse SQL Administrator role
echo "🗄️ Assigning Synapse SQL Administrator role..."
az synapse role assignment create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --role "Synapse SQL Administrator" \
    --assignee "$APP_ID" \
    --only-show-errors

# Assign Synapse Contributor role
echo "✏️ Assigning Synapse Contributor role..."
az synapse role assignment create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --role "Synapse Contributor" \
    --assignee "$APP_ID" \
    --only-show-errors

# Create linked service for billing storage
echo "🔗 Creating linked service to billing storage..."
LINKED_SERVICE_NAME="BillingStorageLinkedService"

# Get storage account key
BILLING_STORAGE_KEY=$(az storage account keys list \
    --resource-group "$BILLING_RG" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --query '[0].value' -o tsv)

# Create linked service JSON
cat > linked_service.json <<EOF
{
  "name": "$LINKED_SERVICE_NAME",
  "properties": {
    "type": "AzureBlobStorage",
    "typeProperties": {
      "connectionString": "DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT_NAME;AccountKey=$BILLING_STORAGE_KEY;EndpointSuffix=core.windows.net"
    }
  }
}
EOF

# Create the linked service
az synapse linked-service create \
    --workspace-name "$SYNAPSE_WORKSPACE" \
    --name "$LINKED_SERVICE_NAME" \
    --file @linked_service.json \
    --only-show-errors

# Clean up temp file
rm linked_service.json

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
echo "✅ Azure Onboarding with Billing Export and Synapse Complete"
echo "============================================================"
echo "📄 Tenant ID:                $TENANT_ID"
echo "📄 App (Client) ID:          $APP_ID"
echo "📄 Client Secret:            $CLIENT_SECRET"
echo ""
echo "💾 Storage Configuration:"
echo "   - Resource Group:         $BILLING_RG"
echo "   - Storage Account:        $STORAGE_ACCOUNT_NAME"
echo "   - Container:              $CONTAINER_NAME"
echo "   - Export Name:            $EXPORT_NAME"
echo ""
echo "🔷 Synapse Configuration:"
echo "   - Workspace:              $SYNAPSE_WORKSPACE"
echo "   - SQL Endpoint:           $SYNAPSE_WORKSPACE.sql.azuresynapse.net"
echo "   - SQL Admin User:         $SQL_ADMIN_USER"
echo "   - SQL Admin Password:     $SQL_ADMIN_PASSWORD"
echo "   - Data Lake Storage:      $SYNAPSE_STORAGE"
echo ""
echo "📄 Assigned Roles:"
echo "   - Cost Management Reader"
echo "   - Monitoring Reader"
echo "   - Storage Blob Data Contributor"
echo "   - Contributor"
echo "   - Synapse Administrator"
echo "   - Synapse SQL Administrator"
echo "   - Synapse Contributor"
echo ""
echo "📝 Next Steps:"
echo "   1. The billing export will run daily and store data in: $STORAGE_ACCOUNT_NAME/$CONTAINER_NAME/billing-data/"
echo "   2. Access Synapse Studio to query your billing data: https://web.azuresynapse.net"
echo "   3. Use OPENROWSET in Synapse to query the billing CSV files directly"
echo ""
echo "📊 Example query to run in Synapse Studio:"
echo "   SELECT * FROM OPENROWSET("
echo "     BULK 'https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$CONTAINER_NAME/billing-data/*.csv',"
echo "     FORMAT = 'CSV', HEADER_ROW = TRUE"
echo "   ) AS billing"
echo "============================================================"