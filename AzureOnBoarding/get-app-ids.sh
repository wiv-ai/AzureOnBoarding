#!/bin/bash

#################################################################################
# get-app-ids.sh
# 
# Purpose: Fetch all relevant IDs for your Azure AD application and service principal
#          Run this in your CSP (managing) tenant to get the IDs needed for Lighthouse
#
# Usage: ./get-app-ids.sh [app-name]
#        If no app name provided, defaults to "wiv_account"
#################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default app name or use provided argument
APP_NAME="${1:-wiv_account}"

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     Azure AD Application & Service Principal ID Fetcher${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if logged in to Azure
echo -e "${YELLOW}Checking Azure login status...${NC}"
if ! az account show &>/dev/null; then
    echo -e "${RED}Not logged in to Azure. Please login first.${NC}"
    echo "Run: az login"
    exit 1
fi

# Get current tenant info
CURRENT_TENANT=$(az account show --query tenantId -o tsv)
CURRENT_TENANT_NAME=$(az account show --query tenantDisplayName -o tsv)

echo -e "${GREEN}✓ Connected to tenant:${NC} $CURRENT_TENANT_NAME"
echo -e "${GREEN}  Tenant ID:${NC} $CURRENT_TENANT"
echo ""

echo -e "${YELLOW}Searching for application:${NC} $APP_NAME"
echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"

# Check if app exists
APP_EXISTS=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv 2>/dev/null)

if [ -z "$APP_EXISTS" ]; then
    echo -e "${RED}✗ Application '$APP_NAME' not found in this tenant${NC}"
    echo ""
    echo "Would you like to create it? (y/n)"
    read -r CREATE_APP
    
    if [[ "$CREATE_APP" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Creating application...${NC}"
        APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
        echo -e "${GREEN}✓ Application created${NC}"
        
        echo -e "${YELLOW}Creating service principal...${NC}"
        SP_OBJECT_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
        echo -e "${GREEN}✓ Service principal created${NC}"
    else
        echo "Exiting..."
        exit 1
    fi
else
    echo -e "${GREEN}✓ Application found${NC}"
fi

# Get Application (Client) ID
echo ""
echo -e "${YELLOW}Fetching Application (Client) ID...${NC}"
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
if [ -n "$APP_ID" ]; then
    echo -e "${GREEN}✓ Application (Client) ID:${NC} $APP_ID"
else
    echo -e "${RED}✗ Could not fetch Application ID${NC}"
fi

# Get App Registration Object ID
echo ""
echo -e "${YELLOW}Fetching App Registration Object ID...${NC}"
APP_OBJECT_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].id" -o tsv)
if [ -n "$APP_OBJECT_ID" ]; then
    echo -e "${GREEN}✓ App Registration Object ID:${NC} $APP_OBJECT_ID"
else
    echo -e "${RED}✗ Could not fetch App Registration Object ID${NC}"
fi

# Get Service Principal Object ID (Most important for Lighthouse)
echo ""
echo -e "${YELLOW}Fetching Service Principal Object ID...${NC}"
SP_OBJECT_ID=$(az ad sp list --display-name "$APP_NAME" --query "[0].id" -o tsv)
if [ -n "$SP_OBJECT_ID" ]; then
    echo -e "${GREEN}✓ Service Principal Object ID:${NC} ${BLUE}$SP_OBJECT_ID${NC} ⭐"
    echo -e "  ${YELLOW}(This is the ID you need for Lighthouse deployments!)${NC}"
else
    echo -e "${RED}✗ Could not fetch Service Principal Object ID${NC}"
    echo -e "${YELLOW}  Creating service principal...${NC}"
    SP_OBJECT_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
    echo -e "${GREEN}✓ Service Principal created with Object ID:${NC} $SP_OBJECT_ID"
fi

# Get Service Principal Enterprise Object ID (same as above, different query)
echo ""
echo -e "${YELLOW}Verifying via Enterprise Applications...${NC}"
SP_ENTERPRISE_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null)
if [ -n "$SP_ENTERPRISE_ID" ]; then
    echo -e "${GREEN}✓ Enterprise App Object ID:${NC} $SP_ENTERPRISE_ID"
    if [ "$SP_ENTERPRISE_ID" == "$SP_OBJECT_ID" ]; then
        echo -e "  ${GREEN}✓ IDs match correctly${NC}"
    fi
fi

# Check for existing secrets
echo ""
echo -e "${YELLOW}Checking for existing client secrets...${NC}"
SECRET_COUNT=$(az ad app credential list --id "$APP_ID" --query "length(@)" -o tsv)
echo -e "${GREEN}✓ Found ${SECRET_COUNT} existing secret(s)${NC}"

# Export to environment variables file
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    SUMMARY FOR LIGHTHOUSE SETUP${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Copy these values for your Lighthouse deployment:${NC}"
echo ""
echo "CSP_TENANT_ID=\"$CURRENT_TENANT\""
echo "CSP_APP_ID=\"$APP_ID\""
echo "CSP_SP_OBJECT_ID=\"$SP_OBJECT_ID\"  # ← Use this for principalId in Lighthouse"
echo ""

# Optionally save to file
echo -e "${YELLOW}Would you like to save these to a .env file? (y/n)${NC}"
read -r SAVE_ENV

if [[ "$SAVE_ENV" =~ ^[Yy]$ ]]; then
    ENV_FILE="lighthouse-config.env"
    cat > "$ENV_FILE" << EOF
# Lighthouse Configuration - Generated $(date)
# Tenant: $CURRENT_TENANT_NAME
# Application: $APP_NAME

# Your CSP/Managing Tenant ID
CSP_TENANT_ID="$CURRENT_TENANT"

# Application (Client) ID
CSP_APP_ID="$APP_ID"

# Service Principal Object ID - Use this for 'principalId' in Lighthouse templates
CSP_SP_OBJECT_ID="$SP_OBJECT_ID"

# Application Display Name
CSP_APP_NAME="$APP_NAME"
EOF
    
    echo -e "${GREEN}✓ Configuration saved to:${NC} $ENV_FILE"
    echo ""
    echo -e "${YELLOW}Source this file before running mass onboarding:${NC}"
    echo "  source $ENV_FILE"
fi

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ ID fetch complete!${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"