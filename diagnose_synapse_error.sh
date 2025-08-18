#!/bin/bash

echo "========================================"
echo "🔍 SYNAPSE WORKSPACE DIAGNOSTIC SCRIPT"
echo "========================================"

# Variables
BILLING_RG="rg-wiv"
SYNAPSE_WORKSPACE="wiv-synapse-billing"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo ""
echo "📋 Configuration:"
echo "  - Resource Group: $BILLING_RG"
echo "  - Workspace Name: $SYNAPSE_WORKSPACE"
echo "  - Subscription: $SUBSCRIPTION_ID"

# Check 1: Resource Group exists
echo ""
echo "1️⃣ Checking Resource Group..."
RG_EXISTS=$(az group exists --name "$BILLING_RG")
if [ "$RG_EXISTS" = "true" ]; then
    LOCATION=$(az group show --name "$BILLING_RG" --query location -o tsv)
    echo "✅ Resource group exists in: $LOCATION"
else
    echo "❌ Resource group does not exist!"
    echo "   Fix: az group create --name $BILLING_RG --location northeurope"
fi

# Check 2: Workspace name availability
echo ""
echo "2️⃣ Checking Workspace Name Availability..."
EXISTING_WS=$(az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$BILLING_RG" --query name -o tsv 2>/dev/null)
if [ -n "$EXISTING_WS" ]; then
    echo "⚠️  Workspace already exists!"
    echo "   Either use existing or delete it:"
    echo "   az synapse workspace delete --name $SYNAPSE_WORKSPACE --resource-group $BILLING_RG --yes"
else
    echo "✅ Workspace name is available"
fi

# Check 3: Check for existing Data Lake Storage
echo ""
echo "3️⃣ Checking for Data Lake Storage Gen2 accounts..."
STORAGE_ACCOUNTS=$(az storage account list --resource-group "$BILLING_RG" --query "[?isHnsEnabled==\`true\`].name" -o tsv 2>/dev/null)
if [ -n "$STORAGE_ACCOUNTS" ]; then
    echo "✅ Found Data Lake Gen2 storage accounts:"
    echo "$STORAGE_ACCOUNTS" | while read -r account; do
        echo "   - $account"
    done
else
    echo "⚠️  No Data Lake Gen2 storage found. Creating one..."
    SYNAPSE_STORAGE="synapsedl$(date +%s | tail -c 6)"
    echo "   Creating: $SYNAPSE_STORAGE"
fi

# Check 4: Provider Registration
echo ""
echo "4️⃣ Checking Azure Provider Registrations..."
SYNAPSE_PROVIDER=$(az provider show --namespace Microsoft.Synapse --query "registrationState" -o tsv)
if [ "$SYNAPSE_PROVIDER" = "Registered" ]; then
    echo "✅ Microsoft.Synapse provider is registered"
else
    echo "❌ Microsoft.Synapse provider not registered!"
    echo "   Registering now..."
    az provider register --namespace Microsoft.Synapse
    echo "   ⏳ This may take a few minutes..."
fi

STORAGE_PROVIDER=$(az provider show --namespace Microsoft.Storage --query "registrationState" -o tsv)
if [ "$STORAGE_PROVIDER" = "Registered" ]; then
    echo "✅ Microsoft.Storage provider is registered"
else
    echo "❌ Microsoft.Storage provider not registered!"
    echo "   Registering now..."
    az provider register --namespace Microsoft.Storage
fi

# Check 5: User Permissions
echo ""
echo "5️⃣ Checking Your Permissions..."
USER_ID=$(az ad signed-in-user show --query id -o tsv)
echo "   Your Object ID: $USER_ID"

# Check for Owner or Contributor role
ROLES=$(az role assignment list --assignee "$USER_ID" --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$BILLING_RG" --query "[].roleDefinitionName" -o tsv 2>/dev/null)
if echo "$ROLES" | grep -qE "Owner|Contributor"; then
    echo "✅ You have sufficient permissions"
else
    echo "⚠️  You may not have sufficient permissions"
    echo "   You need Owner or Contributor role on the resource group"
fi

# Check 6: Region Support
echo ""
echo "6️⃣ Checking Region Support for Synapse..."
REGION="${LOCATION:-northeurope}"
SYNAPSE_REGIONS=$(az provider show --namespace Microsoft.Synapse --query "resourceTypes[?resourceType=='workspaces'].locations" -o tsv | tr '\t' '\n')
if echo "$SYNAPSE_REGIONS" | grep -qi "$REGION"; then
    echo "✅ Region '$REGION' supports Synapse"
else
    echo "❌ Region '$REGION' may not support Synapse"
    echo "   Supported regions include: East US 2, North Europe, West Europe, etc."
fi

# Provide solution
echo ""
echo "========================================"
echo "🔧 RECOMMENDED SOLUTION"
echo "========================================"

if [ "$RG_EXISTS" != "true" ]; then
    echo "1. Create resource group:"
    echo "   az group create --name $BILLING_RG --location northeurope"
    echo ""
fi

if [ "$SYNAPSE_PROVIDER" != "Registered" ]; then
    echo "2. Wait for provider registration (check status):"
    echo "   az provider show --namespace Microsoft.Synapse --query registrationState"
    echo ""
fi

echo "3. Create Data Lake Storage Gen2 (if needed):"
echo "   SYNAPSE_STORAGE=\"synapsedl\$(date +%s | tail -c 6)\""
echo "   az storage account create \\"
echo "       --name \"\$SYNAPSE_STORAGE\" \\"
echo "       --resource-group \"$BILLING_RG\" \\"
echo "       --location \"northeurope\" \\"
echo "       --sku Standard_LRS \\"
echo "       --kind StorageV2 \\"
echo "       --hierarchical-namespace true"
echo ""

echo "4. Create filesystem:"
echo "   az storage fs create \\"
echo "       --name \"synapsefilesystem\" \\"
echo "       --account-name \"\$SYNAPSE_STORAGE\" \\"
echo "       --auth-mode login"
echo ""

echo "5. Create Synapse workspace:"
echo "   az synapse workspace create \\"
echo "       --name \"$SYNAPSE_WORKSPACE\" \\"
echo "       --resource-group \"$BILLING_RG\" \\"
echo "       --storage-account \"\$SYNAPSE_STORAGE\" \\"
echo "       --file-system \"synapsefilesystem\" \\"
echo "       --sql-admin-login-user \"sqladmin\" \\"
echo "       --sql-admin-login-password \"YourSecurePassword123!\" \\"
echo "       --location \"northeurope\""

echo ""
echo "========================================"
echo "✨ Run the main script after fixing any issues above"
echo "========================================"