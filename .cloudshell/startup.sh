#!/bin/bash
#
# Wiv Azure Onboarding - org-level billing account (EA / MCA / CSP partner)
# ------------------------------------------------------------------------
# Cost + FOCUS export at BILLING-ACCOUNT scope: one export covers every
# subscription under the partner/EA/MCA billing account. CSP is supported when
# the partner login can see that billing account (usually agreementType
# MicrosoftCustomerAgreement). Customer tenants with no billing account are
# not supported by this script.
#
# Management group (optional): Reader + Monitoring Reader at MG scope inherit
# to every subscription under the group, including new ones you place there.
# Skip if you do not need inherited access (per-subscription roles still apply).
#
# POC: you can instead grant Reader / Monitoring Reader / Cost Management Reader
# only on subscriptions you pick (no all-billed loop, no management group).
#
# Requires: az CLI (logged in as a tenant/billing admin), curl, python3

set -o pipefail

# Bump this if the Cost Management query API rejects the version.
API_VERSION="2025-03-01"
# Billing role assignment / definition API version.
BILLING_API_VERSION="2024-04-01"

echo ""
echo "🚀 Wiv Azure Onboarding (billing-account: EA/MCA/CSP partner) Starting..."
echo "------------------------------------------------------------------------"

# --- Sanity: tooling ---
for bin in az curl python3; do
  command -v "$bin" >/dev/null 2>&1 || { echo "❌ Missing required tool: $bin"; exit 1; }
done

# --- Login check ---
if ! az account show >/dev/null 2>&1; then
  echo "🔑 Not logged in. Running 'az login'..."
  az login >/dev/null || { echo "❌ Login failed."; exit 1; }
fi

CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null)
CURRENT_USER_NAME=$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null)
[ -n "$CURRENT_USER_NAME" ] && echo "Signed in as: $CURRENT_USER_NAME"

# --- Pick the subscription to host the app registration (NOT a cost scope) ---
echo ""
echo "📦 Available Azure subscriptions:"
az account list --query "[].{Name:name, Id:id}" -o table
read -p "🔹 Subscription ID to host the app registration: " APP_SUBSCRIPTION_ID
az account set --subscription "$APP_SUBSCRIPTION_ID" || { echo "❌ Could not set subscription."; exit 1; }

TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Tenant ID: $TENANT_ID"

# --- App registration + service principal ---
APP_DISPLAY_NAME="wiv_account"
echo ""
echo "🔐 Checking for service principal '$APP_DISPLAY_NAME'..."
APP_ID=$(az ad sp list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv 2>/dev/null)

if [ -z "$APP_ID" ]; then
  echo "🔧 Creating new App Registration..."
  APP_ID=$(az ad app create --display-name "$APP_DISPLAY_NAME" --query appId -o tsv)
  az ad sp create --id "$APP_ID" >/dev/null
  SP_IS_NEW="y"
else
  echo "✅ Service principal exists. App ID: $APP_ID"
  SP_IS_NEW="n"
fi

SP_OBJECT_ID=""
for i in $(seq 1 8); do
  SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null)
  [ -n "$SP_OBJECT_ID" ] && break
  echo "   ...waiting for SP to replicate in AAD ($i/8)"
  sleep 15
done
[ -z "$SP_OBJECT_ID" ] && { echo "❌ Could not resolve SP object ID."; exit 1; }
echo "   SP Object ID: $SP_OBJECT_ID"

# --- Client secret ---
# Only mint a secret for a brand-new SP. Resetting an existing SP's secret would
# invalidate the secret already stored in the Wiv integration, breaking it.
echo ""
if [ "$SP_IS_NEW" = "y" ]; then
  echo "🔑 Creating client secret (2y expiry)..."
  if date --version >/dev/null 2>&1; then
    END_DATE=$(date -d "+2 years" +"%Y-%m-%d")
  else
    END_DATE=$(date -v +2y +"%Y-%m-%d")
  fi
  CLIENT_SECRET=$(az ad app credential reset --id "$APP_ID" --end-date "$END_DATE" --query password -o tsv)
  [ -z "$CLIENT_SECRET" ] && { echo "❌ Failed to create client secret."; exit 1; }
else
  echo "🔑 Service principal already exists - keeping its existing client secret (not resetting)."
  echo "   Reuse the secret you saved during the first onboarding."
  echo "   If you lost it, re-create one with: az ad app credential reset --id $APP_ID"
  CLIENT_SECRET=""
fi

# =====================================================================
# PRIMARY: billing-account cost path (EA / MCA / CSP partner)
# =====================================================================
echo ""
echo "💰 Billing-account cost setup (single export for all subscriptions)"
echo "-------------------------------------------------------------------"
echo "   Validates a partner/EA/MCA billing account is visible to this login."
echo "   CSP partners: sign in to the partner tenant that owns the billing account."

BILLING_TABLE=$(az billing account list --query "[].{Name:name, Agreement:agreementType, Display:displayName}" -o table 2>/dev/null)
if [ -z "$BILLING_TABLE" ]; then
  echo "❌ No billing accounts visible to the current login."
  echo "   This script requires a billing account (EA, MCA, or CSP partner MCA)."
  echo "   If you are a CSP partner, re-run while logged into the partner tenant"
  echo "   with billing-account read access (not a customer tenant without a BA)."
  exit 1
fi

echo "$BILLING_TABLE"
read -p "Paste the Billing account 'Name' to target for cost: " BILLING_ACCOUNT_NAME
[ -z "$BILLING_ACCOUNT_NAME" ] && { echo "❌ Billing account Name is required."; exit 1; }
AGREEMENT=$(az billing account list --query "[?name=='${BILLING_ACCOUNT_NAME}'].agreementType | [0]" -o tsv 2>/dev/null)
[ -z "$AGREEMENT" ] && { echo "❌ Could not resolve agreementType for '$BILLING_ACCOUNT_NAME'."; exit 1; }
echo "   ✅ Billing account validated: $BILLING_ACCOUNT_NAME ($AGREEMENT)"

print_ea_instructions() {
  local guid; guid=$(uuidgen 2>/dev/null || python3 -c "import uuid;print(uuid.uuid4())")
  cat <<EOF

  EA detected. Grant the SP the EnrollmentReader role on the billing account.
  EA billing roles are NOT assignable via 'az role assignment' - use the Billing
  REST API. Reference (CONFIRM the EnrollmentReader roleDefinition GUID here):
    https://learn.microsoft.com/azure/cost-management-billing/manage/assign-roles-azure-service-principals

  Run as an Enterprise Administrator, replacing <ENROLLMENTREADER_ROLE_DEF_GUID>
  (commonly 24f8edb6-1668-4659-b5e2-40bb5f3a7d7e, but verify):

    az rest --method PUT \\
      --url "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/${BILLING_ACCOUNT_NAME}/associatedTenants/${TENANT_ID}/billingRoleAssignments/${guid}?api-version=2024-04-01" \\
      --body '{
        "properties": {
          "principalId": "${SP_OBJECT_ID}",
          "principalTenantId": "${TENANT_ID}",
          "roleDefinitionId": "/providers/Microsoft.Billing/billingAccounts/${BILLING_ACCOUNT_NAME}/billingRoleDefinitions/<ENROLLMENTREADER_ROLE_DEF_GUID>"
        }
      }'

  ⚠️  A lower role (DepartmentReader / Account Owner) needs the EA "DA/AO view
      charges" toggle ON or the SP is denied cost data despite the role.
EOF
}

print_mca_instructions() {
  cat <<EOF

  MCA detected. Grant the SP the 'Billing account reader' role:

    Azure Portal > Cost Management + Billing > select billing account
      > Access control (IAM) > Add > Role: "Billing account reader"
      > assign to the app:  ${APP_DISPLAY_NAME}  (appId ${APP_ID})

  Use 'Billing account reader' (ALL profiles), not 'Billing profile reader'
  (one profile), for full aggregation.
    https://learn.microsoft.com/azure/cost-management-billing/manage/understand-mca-roles
EOF
}

# Attempt to grant a billing role to the SP automatically via REST.
# Resolves the role-definition GUID at runtime by role name (Microsoft anonymizes
# these GUIDs in docs, and they vary), then POSTs createBillingRoleAssignment
# (the 2024-04-01 create path; the old PUT to billingRoleAssignments is read-only).
# Returns: 0 granted, 1 not authorized / call failed, 2 role lookup failed.
grant_billing_role() {
  local ba="$1" sp_oid="$2" tenant="$3" want="$4" defs role_id out
  defs=$(az rest --method GET \
    --url "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/${ba}/billingRoleDefinitions?api-version=${BILLING_API_VERSION}" 2>/dev/null)
  [ -z "$defs" ] && { echo "   ⚠️  Could not read billing role definitions (rights or API version)."; return 2; }
  role_id=$(printf '%s' "$defs" | WANT="$want" python3 -c "
import sys,os,json
want=os.environ['WANT'].strip().lower()
d=json.load(sys.stdin)
exact=sub=''
for r in d.get('value',[]):
    rn=r.get('properties',{}).get('roleName','').strip().lower()
    if rn==want:
        exact=r.get('id',''); break
    if want in rn and not sub:
        sub=r.get('id','')
print(exact or sub)
" 2>/dev/null)
  [ -z "$role_id" ] && { echo "   ⚠️  Role '$want' not found among this account's billing role definitions."; return 2; }
  echo "   Resolved '$want' -> ${role_id##*/}"
  out=$(az rest --method POST \
    --url "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/${ba}/createBillingRoleAssignment?api-version=${BILLING_API_VERSION}" \
    --body "{\"principalId\":\"${sp_oid}\",\"principalTenantId\":\"${tenant}\",\"roleDefinitionId\":\"${role_id}\"}" 2>&1) \
    && { echo "   ✅ Granted '$want' to SP ${sp_oid}."; return 0; }
  if echo "$out" | grep -qiE "Authoriz|Forbidden|403|not have|Insufficient"; then
    echo "   ⚠️  Not authorized to assign billing roles here (need Billing account owner/contributor)."
    return 1
  fi
  echo "   ⚠️  Grant call failed: $out"
  return 1
}

RUN_SMOKE="n"
if [ "$AGREEMENT" = "EnterpriseAgreement" ]; then
  echo "🔑 Attempting automatic 'Enrollment Reader' grant to the SP via REST..."
  if grant_billing_role "$BILLING_ACCOUNT_NAME" "$SP_OBJECT_ID" "$TENANT_ID" "Enrollment Reader"; then
    echo "   (allow a few minutes for propagation before cost rows appear)"
  else
    echo ""; echo "📋 Automatic grant unavailable - grant it manually:"; print_ea_instructions
  fi
  RUN_SMOKE="y"
elif [ "$AGREEMENT" = "MicrosoftCustomerAgreement" ] || [ "$AGREEMENT" = "MicrosoftPartnerAgreement" ]; then
  # MCA covers direct MCA and most modern CSP partner billing accounts.
  # MicrosoftPartnerAgreement is accepted the same way when Azure exposes it.
  echo "🔑 Attempting automatic 'Billing account reader' grant to the SP via REST..."
  if grant_billing_role "$BILLING_ACCOUNT_NAME" "$SP_OBJECT_ID" "$TENANT_ID" "Billing account reader"; then
    echo "   (allow a few minutes for propagation before cost rows appear)"
  else
    echo ""; echo "📋 Automatic grant unavailable - grant it manually:"; print_mca_instructions
  fi
  RUN_SMOKE="y"
else
  echo "❌ Agreement type '$AGREEMENT' is not supported for org-level FOCUS export."
  echo "   Supported: EnterpriseAgreement, MicrosoftCustomerAgreement (incl. CSP partner),"
  echo "   MicrosoftPartnerAgreement."
  exit 1
fi

# --- Smoke test: query cost AS THE SP at billing-account scope ---
if [ "$RUN_SMOKE" = "y" ] && [ -z "$CLIENT_SECRET" ]; then
  echo ""
  echo "ℹ️  Skipping SP smoke test - no new secret was generated for the existing SP."
  echo "   (The smoke test needs a client secret to acquire an SP token.)"
  RUN_SMOKE="n"
fi
if [ "$RUN_SMOKE" = "y" ]; then
  echo ""
  read -p "↪️  Press Enter to run the smoke test (allow a few min if the grant was just made)... " _

  echo "🔍 Acquiring SP token..."
  TOKEN=$(curl -s -X POST "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials" \
    --data-urlencode "client_id=${APP_ID}" \
    --data-urlencode "client_secret=${CLIENT_SECRET}" \
    --data-urlencode "scope=https://management.azure.com/.default" \
    | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)

  if [ -z "$TOKEN" ]; then
    echo "❌ Could not obtain SP token (secret/permissions?). Skipping smoke test."
  else
    SCOPE="/providers/Microsoft.Billing/billingAccounts/${BILLING_ACCOUNT_NAME}"
    URL="https://management.azure.com${SCOPE}/providers/Microsoft.CostManagement/query?api-version=${API_VERSION}"
    BODY='{"type":"ActualCost","timeframe":"MonthToDate","dataset":{"granularity":"None","aggregation":{"totalCost":{"name":"Cost","function":"Sum"}},"grouping":[{"type":"Dimension","name":"SubscriptionId"}]}}'

    RESP=$(curl -s -w $'\n%{http_code}' -X POST "$URL" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$BODY")
    HTTP_CODE=$(printf '%s' "$RESP" | tail -n1)
    PAYLOAD=$(printf '%s' "$RESP" | sed '$d')

    echo ""
    case "$HTTP_CODE" in
      200)
        ROWS=$(printf '%s' "$PAYLOAD" | python3 -c "import sys,json;print(len(json.load(sys.stdin).get('properties',{}).get('rows',[])))" 2>/dev/null)
        if [ "${ROWS:-0}" -gt 0 ] 2>/dev/null; then
          echo "✅ Smoke test PASSED - billing-account cost query works as the SP."
          echo "   Subscriptions aggregated in single call: ${ROWS}"
        else
          echo "⚠️  Authorized but 0 rows returned. Most likely the Billing account"
          echo "    reader role isn't on THIS app yet (token appid must be $APP_ID),"
          echo "    or the grant hasn't propagated (wait a few min), or there is no"
          echo "    month-to-date spend. Grant the role to this appId and re-query."
        fi
        ;;
      401) echo "❌ 401 Unauthorized - token/SP issue (check secret, app config)." ;;
      403) echo "❌ 403 Forbidden - billing role not granted yet, or (EA) DA/AO 'view charges' off." ;;
      404) echo "❌ 404 Not Found - billing account name wrong, or no subscriptions billed here." ;;
      400) echo "❌ 400 Bad Request - often a bad api-version. Edit API_VERSION. Body: $PAYLOAD" ;;
      429) echo "⚠️  429 Throttled - retry shortly." ;;
      *)   echo "❌ Unexpected HTTP $HTTP_CODE. Body: $PAYLOAD" ;;
    esac
  fi
fi

assign_role_with_retry() {
  local object_id="$1" role="$2" scope="$3" tries=0 max=8 out
  while true; do
    out=$(az role assignment create \
            --assignee-object-id "$object_id" \
            --assignee-principal-type ServicePrincipal \
            --role "$role" --scope "$scope" --only-show-errors 2>&1) && return 0
    if echo "$out" | grep -qiE "already exists|RoleAssignmentExists"; then return 0; fi
    if echo "$out" | grep -qiE "PrincipalNotFound|does not exist in the directory|cannot find"; then
      tries=$((tries+1))
      [ "$tries" -ge "$max" ] && { echo "    ⚠️  '$role' not assigned after $max tries (replication)."; return 1; }
      sleep 15; continue
    fi
    echo "    ⚠️  '$role' at $scope failed: $out"; return 1
  done
}

list_billing_account_subscription_ids() {
  local url
  url="https://management.azure.com/providers/Microsoft.Billing/billingAccounts/${BILLING_ACCOUNT_NAME}/billingSubscriptions?api-version=${BILLING_API_VERSION}"
  az rest --method GET --url "$url" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
ids = []
for item in data.get('value') or []:
    props = item.get('properties') or {}
    sid = props.get('subscriptionId') or item.get('name') or ''
    sid = sid.replace('/subscriptions/', '').split('/')[0].strip().lower()
    if sid:
        ids.append(sid)
print(' '.join(ids))
" 2>/dev/null
}

grant_subscription_plane_roles() {
  local sub_id="$1" scope
  [ -z "$sub_id" ] && return 0
  scope="/subscriptions/${sub_id}"
  assign_role_with_retry "$SP_OBJECT_ID" "Reader" "$scope" || true
  assign_role_with_retry "$SP_OBJECT_ID" "Monitoring Reader" "$scope" || true
  assign_role_with_retry "$SP_OBJECT_ID" "Cost Management Reader" "$scope" || true
}

grant_billing_subscriptions_plane_roles() {
  local sub_ids sub_id count=0
  sub_ids=$(list_billing_account_subscription_ids)
  if [ -z "$sub_ids" ]; then
    echo "   ⚠️  No subscriptions returned from billingSubscriptions API; per-sub ARM roles skipped."
    return 0
  fi
  echo "🔒 Assigning Reader / Monitoring Reader / Cost Management Reader on billed subscriptions..."
  for sub_id in $sub_ids; do
    echo "   - $sub_id"
    grant_subscription_plane_roles "$sub_id"
    count=$((count + 1))
  done
  echo "   ✅ Processed $count subscription(s) from billing account"
}

# POC: ARM roles only on chosen subscriptions (not every billed sub, no MG inherit).
parse_subscription_id_list() {
  echo "$1" | tr ',;' ' ' | tr -s '[:space:]' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

grant_selected_subscription_plane_roles() {
  local raw="$1" sub_id count=0
  raw=$(parse_subscription_id_list "$raw")
  if [ -z "$raw" ]; then
    echo "   ⚠️  No subscription IDs given; skipping per-sub ARM roles."
    return 0
  fi
  echo "🔒 POC: assigning Reader / Monitoring Reader / Cost Management Reader on selected subscriptions..."
  for sub_id in $raw; do
    sub_id=$(echo "$sub_id" | tr '[:upper:]' '[:lower:]' | sed 's|/subscriptions/||')
    [ -z "$sub_id" ] && continue
    echo "   - $sub_id"
    grant_subscription_plane_roles "$sub_id"
    count=$((count + 1))
  done
  echo "   ✅ Processed $count selected subscription(s)"
}

ensure_billing_storage_security() {
  local storage_id="$1"
  [ -z "$storage_id" ] && return 0
  az rest --method PATCH \
    --uri "https://management.azure.com${storage_id}?api-version=2023-01-01" \
    --body '{"properties":{"allowBlobPublicAccess":false,"allowSharedKeyAccess":false,"publicNetworkAccess":"Enabled"}}' \
    --output none 2>/dev/null \
    && echo "   ✅ Billing storage hardened (shared-key access disabled)" \
    || echo "   ⚠️  Could not patch billing storage security settings (may need Owner on storage)."
}

# Re-pin subscription context (Cloud Shell can drift after billing REST calls / long pauses).
ensure_app_subscription() {
  local sub_name state err
  err=$(az account set --subscription "$APP_SUBSCRIPTION_ID" 2>&1) || {
    echo "   ❌ Cannot set subscription $APP_SUBSCRIPTION_ID: $err"
    return 1
  }
  sub_name=$(az account show --subscription "$APP_SUBSCRIPTION_ID" --query name -o tsv 2>/dev/null)
  state=$(az account show --subscription "$APP_SUBSCRIPTION_ID" --query state -o tsv 2>/dev/null)
  if [ -z "$sub_name" ]; then
    echo "   ❌ Subscription $APP_SUBSCRIPTION_ID not found for the current login."
    echo "      Tenant: $(az account show --query tenantId -o tsv 2>/dev/null)"
    echo "      Run: az login && az account set --subscription $APP_SUBSCRIPTION_ID"
    return 1
  fi
  if [ "$state" != "Enabled" ]; then
    echo "   ⚠️  Subscription '$sub_name' state is '$state' (expected Enabled)"
  fi
  echo "   Subscription context: $sub_name ($APP_SUBSCRIPTION_ID)"
  return 0
}

# Microsoft.Storage returns misleading SubscriptionNotFound when the RP is not registered.
ensure_resource_provider() {
  local ns="$1" state i
  state=$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null)
  if [ "$state" = "Registered" ]; then
    return 0
  fi
  echo "   Registering $ns (state: ${state:-NotRegistered})..."
  az provider register --namespace "$ns" --only-show-errors 2>/dev/null || true
  for i in $(seq 1 36); do
    state=$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null)
    if [ "$state" = "Registered" ]; then
      echo "   ✅ $ns registered"
      return 0
    fi
    if [ "$i" -le 3 ] || [ $((i % 6)) -eq 0 ]; then
      echo "   ...waiting for $ns ($i/36, state: ${state:-Registering})"
    fi
    sleep 10
  done
  echo "   ❌ $ns still not registered (state: ${state:-unknown})"
  return 1
}

create_storage_account() {
  local name="$1" rg="$2" location="$3" hns="$4" out
  ensure_app_subscription || return 1

  echo "📦 Creating storage account '$name'..."
  if [ "$hns" = "true" ]; then
    out=$(az storage account create \
      --name "$name" \
      --resource-group "$rg" \
      --location "$location" \
      --sku Standard_LRS \
      --kind StorageV2 \
      --hierarchical-namespace true \
      --only-show-errors 2>&1) && { echo "   ✅ Storage account '$name' created"; return 0; }
  else
    out=$(az storage account create \
      --name "$name" \
      --resource-group "$rg" \
      --location "$location" \
      --sku Standard_LRS \
      --kind StorageV2 \
      --only-show-errors 2>&1) && { echo "   ✅ Storage account '$name' created"; return 0; }
  fi

  if echo "$out" | grep -qiE "SubscriptionNotFound|ResourceProviderNotRegistered|not registered"; then
    echo "   ⚠️  CLI create failed (often unregistered Microsoft.Storage): ${out:0:200}"
    ensure_resource_provider "Microsoft.Storage" || return 1
    if [ "$hns" = "true" ]; then
      out=$(az storage account create \
        --name "$name" \
        --resource-group "$rg" \
        --location "$location" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --hierarchical-namespace true \
        --only-show-errors 2>&1) && { echo "   ✅ Storage account '$name' created (after RP register)"; return 0; }
    else
      out=$(az storage account create \
        --name "$name" \
        --resource-group "$rg" \
        --location "$location" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --only-show-errors 2>&1) && { echo "   ✅ Storage account '$name' created (after RP register)"; return 0; }
    fi
  fi

  echo "   Trying REST fallback for '$name'..."
  local hns_prop="false"
  [ "$hns" = "true" ] && hns_prop="true"
  local body
  body=$(cat <<EOF
{
  "sku": {"name": "Standard_LRS"},
  "kind": "StorageV2",
  "location": "${location}",
  "properties": {
    "isHnsEnabled": ${hns_prop},
    "accessTier": "Hot",
    "allowBlobPublicAccess": false,
    "allowSharedKeyAccess": false,
    "publicNetworkAccess": "Enabled"
  }
}
EOF
)
  out=$(az rest --method PUT \
    --uri "https://management.azure.com/subscriptions/${APP_SUBSCRIPTION_ID}/resourceGroups/${rg}/providers/Microsoft.Storage/storageAccounts/${name}?api-version=2023-01-01" \
    --body "$body" 2>&1) && { echo "   ✅ Storage account '$name' created (REST)"; return 0; }

  echo "   ❌ Could not create storage account '$name': ${out:0:300}"
  return 1
}

build_billing_export_body() {
  cat <<EOF
{
  "identity": {
    "type": "SystemAssigned"
  },
  "location": "${AZURE_REGION}",
  "properties": {
    "schedule": {
      "status": "Active",
      "recurrence": "Daily",
      "recurrencePeriod": {
        "from": "${EXPORT_FROM}",
        "to": "${EXPORT_TO}"
      }
    },
    "format": "Parquet",
    "compressionMode": "Snappy",
    "dataOverwriteBehavior": "OverwritePreviousReport",
    "deliveryInfo": {
      "destination": {
        "type": "AzureBlob",
        "resourceId": "${STORAGE_RESOURCE_ID}",
        "container": "${CONTAINER_NAME}",
        "rootFolderPath": "${ROOT_FOLDER}"
      }
    },
    "definition": {
      "type": "FocusCost",
      "timeframe": "MonthToDate",
      "dataSet": {
        "granularity": "Daily",
        "configuration": {
          "dataVersion": "1.0"
        }
      }
    },
    "partitionData": true
  }
}
EOF
}

# FOCUS export at billing-account scope: one export covers ALL billing profiles /
# subscriptions under the EA/MCA/CSP-partner billing account.
# 2025-03-01 is required for dataOverwriteBehavior=OverwritePreviousReport
# (one RunID per month folder). Nested overwriteMode on the preview API does
# not delete previous daily run folders.
COST_EXPORT_API_VERSION="2025-03-01"

# =====================================================================
# FOCUS billing export at billing-account scope (direct blob)
# =====================================================================
BILLING_EXPORT_DEPLOYED="n"
RESOURCE_GROUP=""
STORAGE_ACCOUNT_NAME=""
CONTAINER_NAME=""
ROOT_FOLDER=""
EXPORT_NAME=""
POC_ARM_ROLES_MODE="n"
MG_LABEL="(skipped)"

if [ -n "$BILLING_ACCOUNT_NAME" ]; then
  echo ""
  echo "📊 FOCUS billing export (billing-account scope — all subscriptions)"
  echo "---------------------------------------------------"

  if ! ensure_app_subscription; then
    echo "   ⚠️  Skipping billing export (fix subscription context and re-run)"
  else

  RESOURCE_GROUP="rg-wiv"
  CONTAINER_NAME="billing-exports"
  ROOT_FOLDER="billing-data"
  EXPORT_NAME="WivFocusDailyExport"
  UNIQUE_SUFFIX=$(date +%s | tail -c 6)

  if az group show --name "$RESOURCE_GROUP" --subscription "$APP_SUBSCRIPTION_ID" >/dev/null 2>&1; then
    AZURE_REGION=$(az group show --name "$RESOURCE_GROUP" --subscription "$APP_SUBSCRIPTION_ID" --query location -o tsv)
    echo "   Using existing resource group '$RESOURCE_GROUP' in $AZURE_REGION"
  else
    read -p "   Azure region for rg-wiv [northeurope]: " AZURE_REGION
    AZURE_REGION="${AZURE_REGION:-northeurope}"
    echo "   Creating resource group '$RESOURCE_GROUP' in $AZURE_REGION..."
    if az group create --name "$RESOURCE_GROUP" --location "$AZURE_REGION" --subscription "$APP_SUBSCRIPTION_ID" --only-show-errors; then
      echo "   ✅ Resource group ready"
    else
      echo "   ❌ Could not create resource group in subscription $APP_SUBSCRIPTION_ID"
    fi
  fi

  ensure_app_subscription || true

  echo "🔧 Ensuring required resource providers..."
  ensure_resource_provider "Microsoft.Storage" || echo "   ⚠️  Microsoft.Storage registration incomplete - storage create may fail"
  ensure_resource_provider "Microsoft.CostManagementExports" || echo "   ⚠️  Microsoft.CostManagementExports registration incomplete - billing export may fail"

  STORAGE_ACCOUNT_NAME="wivbill${UNIQUE_SUFFIX}"
  SKIP_EXPORT_CREATION="false"

  echo "🔒 Assigning Cost Management Reader (billing account + host subscription)..."
  az role assignment create \
    --assignee "$APP_ID" \
    --role "Cost Management Reader" \
    --scope "/providers/Microsoft.Billing/billingAccounts/${BILLING_ACCOUNT_NAME}" \
    --only-show-errors 2>/dev/null || true
  az role assignment create \
    --assignee "$APP_ID" \
    --role "Cost Management Reader" \
    --scope "/subscriptions/${APP_SUBSCRIPTION_ID}" \
    --only-show-errors 2>/dev/null || true

  echo ""
  echo "🧪 POC permissions (optional)"
  echo "   Full onboard grants Reader / Monitoring Reader / Cost Management Reader on"
  echo "   every billed subscription, then optionally a management group."
  echo "   POC grants those ARM roles only on subscriptions you pick (no MG inherit)."
  echo ""
  read -p "   Apply ARM roles on selected subscription(s) only (POC)? (y/n): " POC_ARM_ROLES
  if [[ "$POC_ARM_ROLES" =~ ^[Yy]$ ]]; then
    POC_ARM_ROLES_MODE="y"
    echo ""
    echo "   Subscriptions visible to this login:"
    az account list --query "[].{Name:name, Id:id}" -o table
    echo ""
    echo "   Host subscription (already has Cost Management Reader): $APP_SUBSCRIPTION_ID"
    read -p "   Comma-separated subscription IDs for Reader + Monitoring Reader [$APP_SUBSCRIPTION_ID]: " POC_SUB_IDS
    POC_SUB_IDS="${POC_SUB_IDS:-$APP_SUBSCRIPTION_ID}"
    grant_selected_subscription_plane_roles "$POC_SUB_IDS"
    MG_LABEL="(POC: selected subscriptions only)"
  else
    POC_ARM_ROLES_MODE="n"
    grant_billing_subscriptions_plane_roles
  fi

  EXPORT_SCOPE_BASE="https://management.azure.com/providers/Microsoft.Billing/billingAccounts/${BILLING_ACCOUNT_NAME}/providers/Microsoft.CostManagement/exports"
  EXISTING_EXPORT_CHECK=""
  for _export_candidate in "$EXPORT_NAME" DailyBillingExport; do
    _candidate_check=$(az rest --method GET \
      --uri "${EXPORT_SCOPE_BASE}/${_export_candidate}?api-version=${COST_EXPORT_API_VERSION}" 2>/dev/null || true)
    if echo "$_candidate_check" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('properties',{}).get('definition',{}).get('type')=='FocusCost' else 1)" 2>/dev/null; then
      EXISTING_EXPORT_CHECK="$_candidate_check"
      EXPORT_NAME="$_export_candidate"
      break
    fi
  done

  resolve_storage_resource_id() {
    local id="$1" name="$2" found=""
    if [ -n "$id" ]; then
      found=$(az storage account show --ids "$id" --query id -o tsv 2>/dev/null || true)
      if [ -n "$found" ]; then
        STORAGE_RESOURCE_ID="$found"
        STORAGE_ACCOUNT_NAME=$(printf '%s' "$found" | sed 's|.*/storageAccounts/||; s|/.*||')
        return 0
      fi
    fi
    if [ -n "$name" ]; then
      found=$(az storage account list --query "[?name=='${name}'].id | [0]" -o tsv 2>/dev/null || true)
      if [ -n "$found" ]; then
        STORAGE_RESOURCE_ID="$found"
        STORAGE_ACCOUNT_NAME="$name"
        return 0
      fi
    fi
    return 1
  }

  if [ -n "$EXISTING_EXPORT_CHECK" ]; then
    echo "   ✅ FOCUS export '$EXPORT_NAME' already exists on billing account - checking destination storage"
    SKIP_EXPORT_CREATION="true"
    STORAGE_RESOURCE_ID=$(printf '%s' "$EXISTING_EXPORT_CHECK" | python3 -c "import sys,json; print(json.load(sys.stdin)['properties']['deliveryInfo']['destination']['resourceId'])")
    CONTAINER_NAME=$(printf '%s' "$EXISTING_EXPORT_CHECK" | python3 -c "import sys,json; print(json.load(sys.stdin)['properties']['deliveryInfo']['destination']['container'])")
    ROOT_FOLDER=$(printf '%s' "$EXISTING_EXPORT_CHECK" | python3 -c "import sys,json; print(json.load(sys.stdin)['properties']['deliveryInfo']['destination']['rootFolderPath'])")
    STORAGE_ACCOUNT_NAME=$(printf '%s' "$STORAGE_RESOURCE_ID" | sed 's|.*/storageAccounts/||; s|/.*||')
    if ! resolve_storage_resource_id "$STORAGE_RESOURCE_ID" "$STORAGE_ACCOUNT_NAME"; then
      echo "   ⚠️  Export destination storage '$STORAGE_ACCOUNT_NAME' was not found (deleted or in another tenant)."
      echo "       Creating a new billing storage account and retargeting the export."
      STORAGE_ACCOUNT_NAME="wivbill${UNIQUE_SUFFIX}"
      STORAGE_RESOURCE_ID=""
      SKIP_EXPORT_CREATION="false"
      create_storage_account "$STORAGE_ACCOUNT_NAME" "$RESOURCE_GROUP" "$AZURE_REGION" "false" || \
        echo "   ❌ Billing storage account setup failed (need Contributor + Microsoft.Storage registered)"
    else
      BILLING_EXPORT_DEPLOYED="y"
      echo "   ✅ Reusing billing storage '$STORAGE_ACCOUNT_NAME'"
    fi
    EXISTING_FORMAT=$(printf '%s' "$EXISTING_EXPORT_CHECK" | python3 -c "import sys,json; print(json.load(sys.stdin).get('properties',{}).get('format',''))" 2>/dev/null)
    EXISTING_COMPRESSION=$(printf '%s' "$EXISTING_EXPORT_CHECK" | python3 -c "
import sys, json
p = json.load(sys.stdin).get('properties', {})
print((p.get('compressionMode') or p.get('definition', {}).get('dataSet', {}).get('configuration', {}).get('compressionMode', '') or '').lower())
" 2>/dev/null)
    EXISTING_OVERWRITE=$(printf '%s' "$EXISTING_EXPORT_CHECK" | python3 -c "
import sys, json
p = json.load(sys.stdin).get('properties', {})
print(p.get('dataOverwriteBehavior') or str(p.get('definition', {}).get('dataSet', {}).get('configuration', {}).get('overwriteMode', '')))
" 2>/dev/null)
    if [ "$SKIP_EXPORT_CREATION" = "true" ] && { [ "$EXISTING_FORMAT" != "Parquet" ] \
        || [ "$EXISTING_COMPRESSION" != "snappy" ] \
        || [ "$EXISTING_OVERWRITE" != "OverwritePreviousReport" ]; }; then
      echo "   🔄 Updating export '$EXPORT_NAME' to Parquet + Snappy with month overwrite..."
      EXPORT_FROM=$(printf '%s' "$EXISTING_EXPORT_CHECK" | python3 -c "import sys,json; print(json.load(sys.stdin).get('properties',{}).get('schedule',{}).get('recurrencePeriod',{}).get('from',''))" 2>/dev/null)
      EXPORT_TO=$(printf '%s' "$EXISTING_EXPORT_CHECK" | python3 -c "import sys,json; print(json.load(sys.stdin).get('properties',{}).get('schedule',{}).get('recurrencePeriod',{}).get('to',''))" 2>/dev/null)
      if [ -z "$EXPORT_FROM" ] || [ -z "$EXPORT_TO" ]; then
        if date --version >/dev/null 2>&1; then
          EXPORT_FROM=$(date -u +%Y-%m-%dT%H:%M:%SZ)
          EXPORT_TO=$(date -u -d "+1 year" +%Y-%m-%dT%H:%M:%SZ)
        else
          EXPORT_FROM=$(date -u +%Y-%m-%dT%H:%M:%SZ)
          EXPORT_TO=$(date -u -v +1y +%Y-%m-%dT%H:%M:%SZ)
        fi
      fi
      EXPORT_BODY=$(build_billing_export_body)
      az rest --method PUT \
        --uri "${EXPORT_SCOPE_BASE}/${EXPORT_NAME}?api-version=${COST_EXPORT_API_VERSION}" \
        --body "$EXPORT_BODY" --output none 2>/dev/null \
        && echo "   ✅ Export updated to Parquet + Snappy with month overwrite" \
        || echo "   ⚠️  Could not update existing export format - it may still be CSV until recreated"
    fi
  elif ! az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    create_storage_account "$STORAGE_ACCOUNT_NAME" "$RESOURCE_GROUP" "$AZURE_REGION" "false" || \
      echo "   ❌ Billing storage account setup failed (need Contributor + Microsoft.Storage registered)"
  fi

  if [ "$SKIP_EXPORT_CREATION" = "false" ]; then
    STORAGE_RESOURCE_ID=$(az storage account show \
      --name "$STORAGE_ACCOUNT_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --query id -o tsv 2>/dev/null)

    if [ -n "$STORAGE_RESOURCE_ID" ]; then
      echo "📂 Creating container '$CONTAINER_NAME'..."
      az storage container create \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --auth-mode login \
        --only-show-errors >/dev/null 2>&1 || true

      if date --version >/dev/null 2>&1; then
        EXPORT_FROM=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        EXPORT_TO=$(date -u -d "+1 year" +%Y-%m-%dT%H:%M:%SZ)
      else
        EXPORT_FROM=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        EXPORT_TO=$(date -u -v +1y +%Y-%m-%dT%H:%M:%SZ)
      fi

      echo "📊 Creating FOCUS billing export '$EXPORT_NAME' (Parquet/Snappy, billing-account scope - all subscriptions)..."
      create_billing_export() {
        az rest --method PUT \
          --uri "${EXPORT_SCOPE_BASE}/${EXPORT_NAME}?api-version=${COST_EXPORT_API_VERSION}" \
          --body "$EXPORT_BODY" 2>&1
      }

      EXPORT_BODY=$(build_billing_export_body)
      EXPORT_RESPONSE=$(create_billing_export) || true

      if echo "$EXPORT_RESPONSE" | grep -qiE "CostManagementExports|RP Not Registered"; then
        echo "   ⚠️  Microsoft.CostManagementExports not registered on storage subscription - registering..."
        ensure_resource_provider "Microsoft.CostManagementExports" || true
        sleep 10
        EXPORT_RESPONSE=$(create_billing_export) || true
      fi

      if echo "$EXPORT_RESPONSE" | grep -qiE '"name"|"id"'; then
        BILLING_EXPORT_DEPLOYED="y"
        echo "   ✅ FOCUS billing export created at billing-account scope (covers all subscriptions)"
        echo "🔄 Triggering immediate export run..."
        az rest --method POST \
          --uri "${EXPORT_SCOPE_BASE}/${EXPORT_NAME}/run?api-version=${COST_EXPORT_API_VERSION}" \
          --output none 2>/dev/null || echo "   Note: immediate run may not be available yet"
      elif echo "$EXPORT_RESPONSE" | grep -qiE "RBACAccessDenied|Unauthorized|Interactive authentication|does not have authorization"; then
        echo "   ❌ Not authorized to create the billing export at billing-account scope."
        echo "      The export is created with YOUR logged-in identity, which needs a billing"
        echo "      role with export rights on the billing account (e.g. 'Cost Management Contributor'"
        echo "      via Access control, or a Billing account Owner/Contributor role)."
        echo "      Conditional Access may also require re-auth. Fix with:"
        echo "        az logout && az login"
        echo "        # Grant a Cost Management/Billing contributor role on:"
        echo "        #   /providers/Microsoft.Billing/billingAccounts/${BILLING_ACCOUNT_NAME}"
        echo "      Then re-run this script (it will reuse everything already created)."
      else
        echo "   ⚠️  Export create returned: ${EXPORT_RESPONSE:0:300}"
      fi
    fi
  fi

  if [ -z "${STORAGE_RESOURCE_ID:-}" ]; then
    STORAGE_RESOURCE_ID="/subscriptions/${APP_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT_NAME}"
  fi

  echo ""
  echo "🔐 Granting Storage Blob Data Reader on billing export storage to the SP..."
  if resolve_storage_resource_id "${STORAGE_RESOURCE_ID:-}" "$STORAGE_ACCOUNT_NAME"; then
    BILLING_EXPORT_DEPLOYED="y"
    ensure_billing_storage_security "$STORAGE_RESOURCE_ID"
    assign_role_with_retry "$SP_OBJECT_ID" "Storage Blob Data Reader" "$STORAGE_RESOURCE_ID" || true
  else
    echo "   ⚠️  Billing storage not found yet - grant Blob Data Reader after export storage exists."
  fi

  fi
else
  echo ""
  echo "⏭️  Skipping billing export (no billing account selected)"
fi

# =====================================================================
# OPTIONAL: management group (inherited Reader + Monitoring Reader)
# =====================================================================
print_mg_skip_warning() {
  echo ""
  echo "   ⚠️  New subscriptions will not inherit Reader and Monitoring Reader access"
  echo "      from a management group. Per-subscription access on existing billing"
  echo "      subscriptions is unchanged."
}

MG_ID=""
MG_NAMES=()
MG_DISPLAYS=()

if [ "$POC_ARM_ROLES_MODE" = "y" ]; then
  echo ""
  echo "📂 Management group skipped (POC selected-subscription ARM roles)."
  echo "   New subscriptions will not inherit Reader / Monitoring Reader; grant those"
  echo "   roles on each extra subscription if you expand the POC."
else
echo ""
echo "📂 Management group (optional)"
echo "   Assign Reader + Monitoring Reader at a management group so subscriptions"
echo "   under that group inherit access (including new subscriptions you place there)."
echo ""

while IFS=$'\t' read -r mg_name mg_display; do
  [ -z "$mg_name" ] && continue
  MG_NAMES+=("$mg_name")
  MG_DISPLAYS+=("${mg_display:-$mg_name}")
done < <(az account management-group list --query "[].{Name:name, DisplayName:displayName}" -o tsv 2>/dev/null)

if [ "${#MG_NAMES[@]}" -gt 0 ]; then
  echo "   Available management groups:"
  echo ""
  echo "     0) Skip"
  mg_idx=1
  for i in "${!MG_NAMES[@]}"; do
    echo "     $mg_idx) ${MG_NAMES[$i]}  (${MG_DISPLAYS[$i]})"
    mg_idx=$((mg_idx + 1))
  done
  echo ""
  read -p "   Select a number [0-${#MG_NAMES[@]}] (default 0 = skip): " MG_CHOICE
  MG_CHOICE="${MG_CHOICE:-0}"
  if [[ "$MG_CHOICE" =~ ^[0-9]+$ ]] && [ "$MG_CHOICE" -ge 0 ] && [ "$MG_CHOICE" -le "${#MG_NAMES[@]}" ]; then
    if [ "$MG_CHOICE" -eq 0 ]; then
      print_mg_skip_warning
    else
      MG_ID="${MG_NAMES[$((MG_CHOICE - 1))]}"
    fi
  else
    echo "   ⚠️  Invalid selection; skipping management group."
    print_mg_skip_warning
  fi
else
  echo "   (none found — grant Management Group Reader to list groups, or create one below)"
  echo ""
  read -p "   Create a management group now? (y/n): " MK_MG
  if [[ "$MK_MG" =~ ^[Yy]$ ]]; then
    read -p "   New management group ID (no spaces, e.g. wiv-finops): " MG_ID
    read -p "   Display name [$MG_ID]: " MG_DISPLAY
    MG_DISPLAY="${MG_DISPLAY:-$MG_ID}"
    echo "   Creating management group '$MG_ID' (under tenant root)..."
    if az account management-group create --name "$MG_ID" --display-name "$MG_DISPLAY" --only-show-errors >/dev/null 2>&1; then
      echo "   ✅ Created. NOTE: a new MG is empty — inherited access applies only after"
      echo "      subscriptions are moved into it."
      read -p "   Move subscriptions into '$MG_ID' now? (all/specific/no): " MV_CHOICE
      if [[ "$MV_CHOICE" =~ ^[Aa]ll$ ]]; then
        MV_SUBS=$(az account list --query "[].id" -o tsv)
      elif [[ "$MV_CHOICE" =~ ^[Ss]pecific$ ]]; then
        read -p "   Comma-separated subscription IDs to move: " MV_LIST
        MV_SUBS=$(echo "$MV_LIST" | tr ',' ' ')
      else
        MV_SUBS=""
      fi
      for s in $MV_SUBS; do
        echo "     - moving $s ..."
        az account management-group subscription add --name "$MG_ID" --subscription "$s" --only-show-errors 2>/dev/null \
          && echo "       ✅ moved" || echo "       ⚠️  could not move $s (check permissions / already present)"
      done
    else
      echo "   ⚠️  Could not create management group (needs Microsoft.Management/managementGroups/write)."
      MG_ID=""
      print_mg_skip_warning
    fi
  else
    print_mg_skip_warning
  fi
fi

if [ -n "$MG_ID" ]; then
  echo "   Assigning Reader + Monitoring Reader at management group '$MG_ID'..."
  assign_role_with_retry "$SP_OBJECT_ID" "Reader" "/providers/Microsoft.Management/managementGroups/${MG_ID}" || true
  assign_role_with_retry "$SP_OBJECT_ID" "Monitoring Reader" "/providers/Microsoft.Management/managementGroups/${MG_ID}" \
    && MG_LABEL="$MG_ID (inherits to all subs under it)"
fi
fi

# =====================================================================
# OPTIONAL: Microsoft Graph application permissions
# =====================================================================
echo ""
read -p "Grant Microsoft Graph User.Read.All and Group.Read.All (application permissions)? (y/n): " GRANT_PERMS
if [[ "$GRANT_PERMS" =~ ^[Yy]$ ]]; then
  echo "📘 Adding User.Read.All and Group.Read.All (Role) and consenting..."
  az ad app permission add \
    --id "$APP_ID" \
    --api 00000003-0000-0000-c000-000000000000 \
    --api-permissions df02196b-4bf8-4d7d-bdef-90cb943ac5d7=Role \
    --only-show-errors
  az ad app permission add \
    --id "$APP_ID" \
    --api 00000003-0000-0000-c000-000000000000 \
    --api-permissions 5b567255-7703-4780-8f29-8358bdb85264=Role \
    --only-show-errors
  if az ad app permission admin-consent --id "$APP_ID" 2>/dev/null; then
    echo "✅ Admin consent granted."
  else
    echo "⚠️  Admin consent failed - grant manually (App registrations > API permissions)."
  fi
else
  echo "🚫 Skipping Microsoft Graph permissions."
fi

# --- Final output ---
echo ""
echo "✅ Onboarding Complete (billing-account scope)"
echo "--------------------------------------"
echo "📄 Tenant ID:           $TENANT_ID"
echo "📄 App (Client) ID:     $APP_ID"
echo "📄 SP Object ID:        $SP_OBJECT_ID"
echo "📄 Host subscription:   $APP_SUBSCRIPTION_ID"
if [ -n "$BILLING_ACCOUNT_NAME" ]; then
  echo "📄 Billing account:     $BILLING_ACCOUNT_NAME"
  echo "📄 Cost scope:          billingAccounts/$BILLING_ACCOUNT_NAME (${AGREEMENT:-unknown})"
fi
echo "📄 Management group:    $MG_LABEL"
if [ "$BILLING_EXPORT_DEPLOYED" = "y" ]; then
  if [ -z "${STORAGE_RESOURCE_ID:-}" ] && [ -n "${STORAGE_ACCOUNT_NAME:-}" ]; then
    STORAGE_RESOURCE_ID="/subscriptions/${APP_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT_NAME}"
  fi
  echo ""
  echo "📊 FOCUS billing export (blob):"
  echo "📄 Resource group:      $RESOURCE_GROUP"
  echo "📄 Storage account:     $STORAGE_ACCOUNT_NAME"
  echo "📄 Storage resource ID: ${STORAGE_RESOURCE_ID:-}"
  echo "📄 Container:           $CONTAINER_NAME"
  echo "📄 Root folder:         $ROOT_FOLDER"
  echo "📄 Export name:         $EXPORT_NAME (FOCUS, Parquet/Snappy, daily, billing-account scope)"
  echo "📄 Export path:         $ROOT_FOLDER/${EXPORT_NAME}/"
  echo "📄 Billing query:       direct blob (matches Wiv product onboarding)"
fi

echo ""
if [ -n "$CLIENT_SECRET" ]; then
  echo "🔐 CLIENT SECRET (sensitive - store in your secret manager, do not commit):"
  echo "    $CLIENT_SECRET"
else
  echo "🔐 CLIENT SECRET: not regenerated (existing service principal)."
  echo "    Reuse the secret saved during the first onboarding."
  CLIENT_SECRET="<reuse-existing-client-secret>"
fi

# Ready-to-paste Wiv integration secret (client_secret path; no Synapse).
echo ""
echo "📦 Wiv integration secret (paste into manual Azure integration / share with Wiv):"
if [ "$BILLING_EXPORT_DEPLOYED" = "y" ] && [ -n "${STORAGE_ACCOUNT_NAME:-}" ]; then
  cat <<EOF
{
  "auth_method": "client_secret",
  "tenant_id": "${TENANT_ID}",
  "app_id": "${APP_ID}",
  "client_secret": "${CLIENT_SECRET}",
  "sp_object_id": "${SP_OBJECT_ID}",
  "billing_account_name": "${BILLING_ACCOUNT_NAME}",
  "billing_query_backend": "blob",
  "billing_storage_account": "${STORAGE_ACCOUNT_NAME}",
  "billing_storage_resource_id": "${STORAGE_RESOURCE_ID}",
  "billing_container": "${CONTAINER_NAME}",
  "billing_root_folder": "${ROOT_FOLDER}",
  "billing_export_name": "${EXPORT_NAME}",
  "subscription_id": "${APP_SUBSCRIPTION_ID}"
}
EOF
else
  cat <<EOF
{
  "auth_method": "client_secret",
  "tenant_id": "${TENANT_ID}",
  "app_id": "${APP_ID}",
  "client_secret": "${CLIENT_SECRET}",
  "sp_object_id": "${SP_OBJECT_ID}",
  "billing_account_name": "${BILLING_ACCOUNT_NAME}",
  "billing_query_backend": "blob",
  "subscription_id": "${APP_SUBSCRIPTION_ID}"
}
EOF
  echo "   (billing storage / export fields omitted — FOCUS export was not deployed in this run)"
fi
if [ "$CLIENT_SECRET" = "<reuse-existing-client-secret>" ]; then
  echo "   Replace client_secret with the value saved from the first onboarding."
fi
