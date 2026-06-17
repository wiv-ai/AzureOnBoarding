#!/bin/bash
#
# Wiv Azure Onboarding - org-level (EA/MCA), no per-subscription loops
# --------------------------------------------------------------------
# Cost is pulled at BILLING-ACCOUNT scope, which aggregates every subscription
# under one EA/MCA account in a single Cost Management query. There is NO
# per-subscription cost path here by design.
#
# Metrics (Monitoring Reader) has no billing-account equivalent, so the only
# org-level (non per-subscription) way to grant it is at a MANAGEMENT-GROUP
# scope, which inherits to all subscriptions under the group. That step is
# optional - press Enter to skip it.
#
# Requires: az CLI (logged in as a tenant/billing admin), curl, python3

set -o pipefail

# Bump this if the Cost Management query API rejects the version.
API_VERSION="2025-03-01"
# Billing role assignment / definition API version.
BILLING_API_VERSION="2024-04-01"

echo ""
echo "🚀 Wiv Azure Onboarding (org-level, EA/MCA) Starting..."
echo "-------------------------------------------------------"

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
# PRIMARY: billing-account cost path (org-level, EA/MCA)
# =====================================================================
echo ""
echo "💰 Billing-account cost setup (single-call aggregation)"
echo "-------------------------------------------------------"

BILLING_TABLE=$(az billing account list --query "[].{Name:name, Agreement:agreementType, Display:displayName}" -o table 2>/dev/null)
if [ -z "$BILLING_TABLE" ]; then
  echo "❌ No billing accounts visible to the current login. You either lack billing"
  echo "   read access, or this tenant is MOSP/CSP (no org-level billing scope)."
  echo "   Cannot proceed with the org-level cost path."
  BILLING_ACCOUNT_NAME=""
  AGREEMENT=""
else
  echo "$BILLING_TABLE"
  read -p "Paste the Billing account 'Name' to target for cost: " BILLING_ACCOUNT_NAME
  AGREEMENT=$(az billing account list --query "[?name=='${BILLING_ACCOUNT_NAME}'].agreementType | [0]" -o tsv 2>/dev/null)
fi

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
elif [ "$AGREEMENT" = "MicrosoftCustomerAgreement" ]; then
  echo "🔑 Attempting automatic 'Billing account reader' grant to the SP via REST..."
  if grant_billing_role "$BILLING_ACCOUNT_NAME" "$SP_OBJECT_ID" "$TENANT_ID" "Billing account reader"; then
    echo "   (allow a few minutes for propagation before cost rows appear)"
  else
    echo ""; echo "📋 Automatic grant unavailable - grant it manually:"; print_mca_instructions
  fi
  RUN_SMOKE="y"
elif [ -n "$AGREEMENT" ]; then
  echo "⚠️  Agreement type '$AGREEMENT' has no org-level billing scope. Cannot proceed org-level."
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
    "accessTier": "Hot"
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
  "properties": {
    "schedule": {
      "status": "Active",
      "recurrence": "Daily",
      "recurrencePeriod": {
        "from": "${EXPORT_FROM}",
        "to": "${EXPORT_TO}"
      }
    },
    "format": "Csv",
    "deliveryInfo": {
      "destination": {
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
          "dataVersion": "1.0",
          "compressionMode": "None",
          "overwriteMode": true
        }
      }
    },
    "partitionData": true
  }
}
EOF
}

# FOCUS export at billing-account scope: one export covers ALL billing profiles /
# subscriptions in the MCA (MCA billing account supports FocusCost; management-group
# scope only supports Usage). No fallback to subscription scope.
COST_EXPORT_API_VERSION="2023-07-01-preview"

# =====================================================================
# Billing export + Synapse Analytics (FOCUS export at billing-account scope)
# =====================================================================
SYNAPSE_DEPLOYED="n"
RESOURCE_GROUP=""
STORAGE_ACCOUNT_NAME=""
CONTAINER_NAME=""
ROOT_FOLDER=""
EXPORT_NAME=""
SYNAPSE_WORKSPACE=""
BILLING_DATABASE="BillingAnalytics"

if [ -n "$BILLING_ACCOUNT_NAME" ]; then
  echo ""
  echo "📊 Billing export + Synapse Analytics (automated)"
  echo "---------------------------------------------------"

  if ! ensure_app_subscription; then
    echo "   ⚠️  Skipping billing export + Synapse (fix subscription context and re-run)"
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
  ensure_resource_provider "Microsoft.Synapse" || echo "   ⚠️  Microsoft.Synapse registration incomplete - Synapse create may fail"
  ensure_resource_provider "Microsoft.Sql" || echo "   ⚠️  Microsoft.Sql registration incomplete - Synapse SQL pool requires this"

  STORAGE_ACCOUNT_NAME="wivbill${UNIQUE_SUFFIX}"
  SYNAPSE_STORAGE="wivsyn${UNIQUE_SUFFIX}"
  SYNAPSE_WORKSPACE="wiv-synapse-${UNIQUE_SUFFIX}"
  FILESYSTEM_NAME="synapsefilesystem"
  SKIP_EXPORT_CREATION="false"

  echo "🔒 Assigning Cost Management Reader (billing account + subscription)..."
  if [ -n "$BILLING_ACCOUNT_NAME" ]; then
    az role assignment create \
      --assignee "$APP_ID" \
      --role "Cost Management Reader" \
      --scope "/providers/Microsoft.Billing/billingAccounts/${BILLING_ACCOUNT_NAME}" \
      --only-show-errors 2>/dev/null || true
  fi
  az role assignment create \
    --assignee "$APP_ID" \
    --role "Cost Management Reader" \
    --scope "/subscriptions/${APP_SUBSCRIPTION_ID}" \
    --only-show-errors 2>/dev/null || true

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

  if [ -n "$EXISTING_EXPORT_CHECK" ]; then
    echo "   ✅ FOCUS export '$EXPORT_NAME' already exists on billing account - reusing destination storage"
    SKIP_EXPORT_CREATION="true"
    STORAGE_RESOURCE_ID=$(printf '%s' "$EXISTING_EXPORT_CHECK" | python3 -c "import sys,json; print(json.load(sys.stdin)['properties']['deliveryInfo']['destination']['resourceId'])")
    CONTAINER_NAME=$(printf '%s' "$EXISTING_EXPORT_CHECK" | python3 -c "import sys,json; print(json.load(sys.stdin)['properties']['deliveryInfo']['destination']['container'])")
    ROOT_FOLDER=$(printf '%s' "$EXISTING_EXPORT_CHECK" | python3 -c "import sys,json; print(json.load(sys.stdin)['properties']['deliveryInfo']['destination']['rootFolderPath'])")
    STORAGE_ACCOUNT_NAME=$(printf '%s' "$STORAGE_RESOURCE_ID" | sed 's|.*/storageAccounts/||; s|/.*||')
  elif ! az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    create_storage_account "$STORAGE_ACCOUNT_NAME" "$RESOURCE_GROUP" "$AZURE_REGION" "true" || \
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

      echo "📊 Creating FOCUS billing export '$EXPORT_NAME' (billing-account scope - all subscriptions)..."
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
  echo "🔷 Setting up Synapse Analytics workspace..."
  ensure_app_subscription || true
  SYNAPSE_REGION=""
  SYNAPSE_OK="n"
  SYNAPSE_EXISTS=$(az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$RESOURCE_GROUP" --subscription "$APP_SUBSCRIPTION_ID" --query name -o tsv 2>/dev/null)

  # Subscriptions cap Synapse workspaces (PAYG default: 2). Offer to reuse an existing one, but let the user choose.
  if [ -z "$SYNAPSE_EXISTS" ]; then
    EXISTING_WS_NAMES=$(az synapse workspace list --subscription "$APP_SUBSCRIPTION_ID" --query "[].name" -o tsv 2>/dev/null)
    EXISTING_WS_COUNT=$(printf '%s\n' "$EXISTING_WS_NAMES" | grep -c . 2>/dev/null)
    if [ "${EXISTING_WS_COUNT:-0}" -gt 0 ]; then
      echo "   Existing Synapse workspaces in this subscription:"
      az synapse workspace list --subscription "$APP_SUBSCRIPTION_ID" \
        --query "[].{Name:name, Region:location, ResourceGroup:resourceGroup}" -o table 2>/dev/null | sed 's/^/     /'
      echo ""
      read -p "   Reuse an existing workspace instead of creating a new one? (y/n): " _REUSE_CHOICE
      if [[ "$_REUSE_CHOICE" =~ ^[Yy]$ ]]; then
        if [ "${EXISTING_WS_COUNT:-0}" -eq 1 ]; then
          REUSE_WS=$(printf '%s\n' "$EXISTING_WS_NAMES" | head -n1)
          echo "   Only one workspace found - reusing '$REUSE_WS'"
        else
          read -p "   Workspace name to reuse: " REUSE_WS
        fi
        if [ -n "$REUSE_WS" ]; then
          REUSE_RG=$(az synapse workspace list --subscription "$APP_SUBSCRIPTION_ID" \
            --query "[?name=='${REUSE_WS}'].resourceGroup | [0]" -o tsv 2>/dev/null)
          if [ -n "$REUSE_RG" ]; then
            SYNAPSE_WORKSPACE="$REUSE_WS"
            RESOURCE_GROUP="$REUSE_RG"
            SYNAPSE_EXISTS="$REUSE_WS"
          else
            echo "   ⚠️  '$REUSE_WS' not found - will create a new workspace instead."
          fi
        fi
      fi
    fi
  fi

  if [ -n "$SYNAPSE_EXISTS" ]; then
    echo "   ✅ Synapse workspace '$SYNAPSE_WORKSPACE' already exists"
    SYNAPSE_OK="y"
    SYNAPSE_REGION=$(az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$RESOURCE_GROUP" --subscription "$APP_SUBSCRIPTION_ID" --query location -o tsv 2>/dev/null)
    SYNAPSE_STORAGE=$(az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$RESOURCE_GROUP" --subscription "$APP_SUBSCRIPTION_ID" \
      --query "defaultDataLakeStorage.accountUrl" -o tsv | sed 's|https://||; s|.dfs.core.windows.net||')
    FILESYSTEM_NAME=$(az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$RESOURCE_GROUP" --subscription "$APP_SUBSCRIPTION_ID" \
      --query "defaultDataLakeStorage.filesystem" -o tsv)
  else
    SQL_ADMIN_USER="sqladminuser"
    SQL_ADMIN_PASSWORD="P@ssw0rd${UNIQUE_SUFFIX}!"
    SYNAPSE_CREATE_OUT="not-attempted"

    echo "   Synapse must be created in a region that allows SQL provisioning for this subscription."
    echo "   Suggested SQL-capable regions: westeurope, northeurope, eastus, westus2, swedencentral, uksouth"
    echo "   (billing storage stays in $AZURE_REGION; Synapse serverless reads it cross-region)"

    while true; do
      read -p "   Synapse region [$AZURE_REGION] (or 'skip' to skip Synapse): " SYNAPSE_REGION
      SYNAPSE_REGION="${SYNAPSE_REGION:-$AZURE_REGION}"

      if [ "$SYNAPSE_REGION" = "skip" ]; then
        echo "   ⏭️  Skipping Synapse workspace creation (per user choice)."
        SYNAPSE_CREATE_OUT="skipped"
        break
      fi

      if ! az account list-locations --query "[?name=='${SYNAPSE_REGION}'].name | [0]" -o tsv 2>/dev/null | grep -q .; then
        echo "   ⚠️  '$SYNAPSE_REGION' is not a valid Azure region name. Try again (e.g. westeurope)."
        continue
      fi

      REGION_TAG=$(printf '%s' "$SYNAPSE_REGION" | tr -cd 'a-z0-9' | cut -c1-6)
      if [ "$SYNAPSE_REGION" = "$AZURE_REGION" ]; then
        TRY_SYNAPSE_STORAGE="$SYNAPSE_STORAGE"
      else
        TRY_SYNAPSE_STORAGE=$(printf 'wivsyn%s%s' "$UNIQUE_SUFFIX" "$REGION_TAG" | cut -c1-24)
      fi

      if ! az storage account show --name "$TRY_SYNAPSE_STORAGE" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        create_storage_account "$TRY_SYNAPSE_STORAGE" "$RESOURCE_GROUP" "$SYNAPSE_REGION" "true" || {
          echo "   ⚠️  Could not create Synapse storage in $SYNAPSE_REGION. Pick another region."
          continue
        }
      fi

      DATALAKE_RESOURCE_ID=$(az storage account show \
        --name "$TRY_SYNAPSE_STORAGE" \
        --resource-group "$RESOURCE_GROUP" \
        --query id -o tsv 2>/dev/null)
      [ -z "$DATALAKE_RESOURCE_ID" ] && { echo "   ⚠️  Synapse storage not found after create. Pick another region."; continue; }

      assign_role_with_retry "$SP_OBJECT_ID" "Storage Blob Data Contributor" "$DATALAKE_RESOURCE_ID" || true
      az storage fs create \
        --name "$FILESYSTEM_NAME" \
        --account-name "$TRY_SYNAPSE_STORAGE" \
        --auth-mode login \
        --only-show-errors >/dev/null 2>&1 || true

      echo "🏗️  Creating Synapse workspace in $SYNAPSE_REGION (may take 5-10 minutes)..."
      ensure_app_subscription || true
      SYNAPSE_CREATE_OUT=$(az synapse workspace create \
        --name "$SYNAPSE_WORKSPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$TRY_SYNAPSE_STORAGE" \
        --file-system "$FILESYSTEM_NAME" \
        --sql-admin-login-user "$SQL_ADMIN_USER" \
        --sql-admin-login-password "$SQL_ADMIN_PASSWORD" \
        --location "$SYNAPSE_REGION" \
        --only-show-errors 2>&1) && SYNAPSE_CREATE_OUT=""

      if [ -n "$SYNAPSE_CREATE_OUT" ] && echo "$SYNAPSE_CREATE_OUT" | grep -qiE "CustomerSubscriptionNotRegisteredWithSqlRp|Microsoft\.Sql"; then
        echo "   ⚠️  Microsoft.Sql not registered - registering and retrying in $SYNAPSE_REGION..."
        ensure_resource_provider "Microsoft.Sql" || true
        sleep 15
        SYNAPSE_CREATE_OUT=$(az synapse workspace create \
          --name "$SYNAPSE_WORKSPACE" \
          --resource-group "$RESOURCE_GROUP" \
          --storage-account "$TRY_SYNAPSE_STORAGE" \
          --file-system "$FILESYSTEM_NAME" \
          --sql-admin-login-user "$SQL_ADMIN_USER" \
          --sql-admin-login-password "$SQL_ADMIN_PASSWORD" \
          --location "$SYNAPSE_REGION" \
          --only-show-errors 2>&1) && SYNAPSE_CREATE_OUT=""
      fi

      if [ -z "$SYNAPSE_CREATE_OUT" ]; then
        SYNAPSE_STORAGE="$TRY_SYNAPSE_STORAGE"
        SYNAPSE_OK="y"
        echo "   ✅ Synapse workspace created in $SYNAPSE_REGION"
        break
      fi

      if echo "$SYNAPSE_CREATE_OUT" | grep -qiE "SqlServerRegionDoesNotAllowProvisioning|not accepting creation"; then
        echo "   ⚠️  $SYNAPSE_REGION does not allow new SQL servers for this subscription. Choose a different region."
        continue
      fi

      if echo "$SYNAPSE_CREATE_OUT" | grep -qiE "ReachedPerSubscriptionWorkspaceLimit|maximum number of Synapse"; then
        echo "   ⚠️  Subscription Synapse workspace limit reached - attempting to reuse an existing workspace..."
        REUSE_WS=$(az synapse workspace list --subscription "$APP_SUBSCRIPTION_ID" \
          --query "[?starts_with(name, 'wiv-synapse-')].name | [0]" -o tsv 2>/dev/null)
        [ -z "$REUSE_WS" ] && REUSE_WS=$(az synapse workspace list --subscription "$APP_SUBSCRIPTION_ID" --query "[0].name" -o tsv 2>/dev/null)
        if [ -n "$REUSE_WS" ]; then
          REUSE_RG=$(az synapse workspace list --subscription "$APP_SUBSCRIPTION_ID" \
            --query "[?name=='${REUSE_WS}'].resourceGroup | [0]" -o tsv 2>/dev/null)
          SYNAPSE_WORKSPACE="$REUSE_WS"
          [ -n "$REUSE_RG" ] && RESOURCE_GROUP="$REUSE_RG"
          SYNAPSE_REGION=$(az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$RESOURCE_GROUP" --query location -o tsv 2>/dev/null)
          SYNAPSE_STORAGE=$(az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$RESOURCE_GROUP" \
            --query "defaultDataLakeStorage.accountUrl" -o tsv | sed 's|https://||; s|.dfs.core.windows.net||')
          FILESYSTEM_NAME=$(az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$RESOURCE_GROUP" \
            --query "defaultDataLakeStorage.filesystem" -o tsv)
          SYNAPSE_CREATE_OUT=""
          SYNAPSE_OK="y"
          echo "   ♻️  Reusing existing Synapse workspace '$SYNAPSE_WORKSPACE'"
        else
          echo "   ❌ No existing Synapse workspace found to reuse. Delete an unused workspace or request a limit increase."
        fi
        break
      fi

      echo "   ❌ Synapse workspace creation failed in $SYNAPSE_REGION: ${SYNAPSE_CREATE_OUT:0:400}"
      read -p "   Try a different region? (y/n): " _RETRY_SYNAPSE
      [[ "$_RETRY_SYNAPSE" =~ ^[Yy]$ ]] && continue
      break
    done

    if [ "$SYNAPSE_CREATE_OUT" = "skipped" ]; then
      echo "   ⏭️  Synapse not created. Re-run later and choose a region to enable analytics."
    elif [ -n "$SYNAPSE_CREATE_OUT" ] && [ -z "$(az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$RESOURCE_GROUP" --query name -o tsv 2>/dev/null)" ]; then
      echo "   ❌ Synapse workspace was not created."
      echo "      Existing workspaces count toward the per-subscription limit (PAYG default: 2)."
      echo "      Delete an unused one (az synapse workspace delete) or request a limit increase, then re-run."
    fi
  fi

  if [ "$SYNAPSE_OK" != "y" ]; then
    for _i in 1 2 3; do
      if az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$RESOURCE_GROUP" --subscription "$APP_SUBSCRIPTION_ID" >/dev/null 2>&1; then
        SYNAPSE_OK="y"
        break
      fi
      sleep 10
    done
  fi

  if [ "$SYNAPSE_OK" = "y" ]; then
    echo "⏳ Waiting for Synapse workspace to be ready..."
    az synapse workspace wait --resource-group "$RESOURCE_GROUP" --workspace-name "$SYNAPSE_WORKSPACE" --subscription "$APP_SUBSCRIPTION_ID" --created 2>/dev/null || sleep 30

    echo "🔥 Configuring Synapse firewall..."
    # 0.0.0.0-0.0.0.0 is the special "Allow Azure services" toggle - it does NOT let
    # real client IPs (Cloud Shell egress or your browser for Synapse Studio) connect.
    az synapse workspace firewall-rule create \
      --name "AllowAllWindowsAzureIps" \
      --workspace-name "$SYNAPSE_WORKSPACE" \
      --resource-group "$RESOURCE_GROUP" \
      --subscription "$APP_SUBSCRIPTION_ID" \
      --start-ip-address "0.0.0.0" \
      --end-ip-address "0.0.0.0" \
      --only-show-errors >/dev/null 2>&1 || true
    # Allow all client IPs so both this Cloud Shell and Synapse Studio (browser) can
    # reach the serverless SQL endpoint. Access is still gated by Entra auth + SQL perms.
    az synapse workspace firewall-rule create \
      --name "AllowAll" \
      --workspace-name "$SYNAPSE_WORKSPACE" \
      --resource-group "$RESOURCE_GROUP" \
      --subscription "$APP_SUBSCRIPTION_ID" \
      --start-ip-address "0.0.0.0" \
      --end-ip-address "255.255.255.255" \
      --only-show-errors >/dev/null 2>&1 || true
    # Also pin this client's public IP explicitly (belt and suspenders).
    CLIENT_IP=$(curl -s https://api.ipify.org 2>/dev/null || echo "")
    if [ -n "$CLIENT_IP" ]; then
      az synapse workspace firewall-rule create \
        --name "ClientIP_$(echo "$CLIENT_IP" | tr . _)" \
        --workspace-name "$SYNAPSE_WORKSPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --subscription "$APP_SUBSCRIPTION_ID" \
        --start-ip-address "$CLIENT_IP" \
        --end-ip-address "$CLIENT_IP" \
        --only-show-errors >/dev/null 2>&1 || true
    fi
    echo "   ⏳ Waiting ~60s for firewall rules to propagate..."
    sleep 60

    echo "🔐 Granting Synapse roles..."
    if [ -n "$CURRENT_USER_ID" ]; then
      az synapse role assignment create \
        --workspace-name "$SYNAPSE_WORKSPACE" \
        --role "Synapse Administrator" \
        --assignee "$CURRENT_USER_ID" \
        --only-show-errors >/dev/null 2>&1 || true
      az synapse role assignment create \
        --workspace-name "$SYNAPSE_WORKSPACE" \
        --role "Synapse SQL Administrator" \
        --assignee "$CURRENT_USER_ID" \
        --only-show-errors >/dev/null 2>&1 || true
    fi
    az synapse role assignment create \
      --workspace-name "$SYNAPSE_WORKSPACE" \
      --role "Synapse Administrator" \
      --assignee "$SP_OBJECT_ID" \
      --only-show-errors >/dev/null 2>&1 || true
    az synapse role assignment create \
      --workspace-name "$SYNAPSE_WORKSPACE" \
      --role "Synapse SQL Administrator" \
      --assignee "$SP_OBJECT_ID" \
      --only-show-errors >/dev/null 2>&1 || true

    SYNAPSE_IDENTITY=$(az synapse workspace show \
      --name "$SYNAPSE_WORKSPACE" \
      --resource-group "$RESOURCE_GROUP" \
      --subscription "$APP_SUBSCRIPTION_ID" \
      --query "identity.principalId" -o tsv 2>/dev/null)

    echo "🔐 Granting storage access on billing export storage..."
    # On reuse (existing workspace, NEW billing storage) this grant is what makes the
    # serverless view readable. Use the verified/retried path and confirm it landed,
    # rather than a silent one-shot, so the first BillingData query doesn't fail later.
    if [ -n "$SYNAPSE_IDENTITY" ]; then
      assign_role_with_retry "$SYNAPSE_IDENTITY" "Storage Blob Data Reader" "$STORAGE_RESOURCE_ID" || \
        echo "   ⚠️  Could not confirm Storage Blob Data Reader for the Synapse identity."
      if az role assignment list --assignee "$SYNAPSE_IDENTITY" --scope "$STORAGE_RESOURCE_ID" \
           --query "[?roleDefinitionName=='Storage Blob Data Reader'] | [0]" -o tsv 2>/dev/null | grep -q .; then
        echo "   ✅ Synapse identity has Storage Blob Data Reader on $STORAGE_ACCOUNT_NAME"
      else
        echo "   ⚠️  Grant not visible yet (will warm up after view creation)."
      fi
    fi
    assign_role_with_retry "$SP_OBJECT_ID" "Storage Blob Data Reader" "$STORAGE_RESOURCE_ID" || true
    if [ -n "$CURRENT_USER_ID" ]; then
      az role assignment create \
        --role "Storage Blob Data Reader" \
        --assignee "$CURRENT_USER_ID" \
        --scope "$STORAGE_RESOURCE_ID" \
        --only-show-errors >/dev/null 2>&1 || true
    fi

    echo "⏳ Waiting for permissions to propagate..."
    sleep 45

    echo ""
    echo "🔧 Creating $BILLING_DATABASE database and FOCUS views..."
    ACCESS_TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>/dev/null)
    DATABASE_CREATED=false

    if [ -n "$ACCESS_TOKEN" ]; then
      # IMPORTANT: the Synapse serverless SQL pool only speaks the TDS protocol on
      # ${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net:1433. There is NO HTTP REST
      # "run query" API - posting to /sql/databases/<db>/query always returns HTTP 500.
      # So we run T-SQL through a real driver (mssql-python, or pyodbc + msodbcsql18),
      # authenticating as the current Cloud Shell user (granted Synapse/SQL admin above).
      SQL_SERVER="${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net"

      echo "  Preparing SQL client (serverless SQL pool needs a TDS driver)..."
      SQL_DRIVER=""
      if python3 -c 'import mssql_python' 2>/dev/null; then
        SQL_DRIVER="mssql_python"
      elif python3 -m pip install --quiet --user --disable-pip-version-check mssql-python 2>/dev/null && python3 -c 'import mssql_python' 2>/dev/null; then
        SQL_DRIVER="mssql_python"
      elif python3 -c 'import pyodbc' 2>/dev/null; then
        SQL_DRIVER="pyodbc"
      else
        echo "    Installing ODBC driver + pyodbc (one-time)..."
        sudo ACCEPT_EULA=Y tdnf install -y msodbcsql18 >/dev/null 2>&1 || true
        if python3 -m pip install --quiet --user --disable-pip-version-check pyodbc 2>/dev/null && python3 -c 'import pyodbc' 2>/dev/null; then
          SQL_DRIVER="pyodbc"
        fi
      fi
      if [ -n "$SQL_DRIVER" ]; then
        echo "    ✅ SQL client ready ($SQL_DRIVER)"
      else
        echo "    ⚠️  Could not install a SQL driver - Synapse SQL setup will be skipped"
      fi

      # Python helper: runs one T-SQL batch from stdin, retrying while the serverless
      # pool resumes from cold (it pauses when idle and takes ~30-90s to wake up).
      SQL_HELPER="$HOME/.wiv_sqlexec.py"
      cat > "$SQL_HELPER" <<'PYEOF'
import os, sys, time

server = sys.argv[1]
database = sys.argv[2]
query = sys.stdin.read()
token = os.environ.get("WIV_SQL_TOKEN", "")
driver = os.environ.get("WIV_SQL_DRIVER", "")


def connect_mssql():
    from mssql_python import connect
    return connect(
        f"Server={server};Database={database};"
        "Authentication=ActiveDirectoryDefault;Encrypt=yes;"
        "TrustServerCertificate=no;"
    )


def connect_pyodbc():
    import struct
    import pyodbc
    SQL_COPT_SS_ACCESS_TOKEN = 1256
    exptoken = b"".join(bytes([b, 0]) for b in token.encode("utf-8"))
    tokenstruct = struct.pack("=i", len(exptoken)) + exptoken
    return pyodbc.connect(
        f"Driver={{ODBC Driver 18 for SQL Server}};Server={server};"
        f"Database={database};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=60;",
        attrs_before={SQL_COPT_SS_ACCESS_TOKEN: tokenstruct},
    )


make_conn = connect_mssql if driver == "mssql_python" else connect_pyodbc

last = ""
for attempt in range(8):
    try:
        conn = make_conn()
        try:
            conn.setautocommit(True)
        except Exception:
            try:
                conn.autocommit = True
            except Exception:
                pass
        cur = conn.cursor()
        cur.execute(query)
        try:
            cur.fetchall()
        except Exception:
            pass
        cur.close()
        conn.close()
        print("OK")
        sys.exit(0)
    except Exception as exc:
        last = str(exc)
        transient = any(
            s in last
            for s in ("40613", "resuming", "is not currently available", "timeout",
                      "Timeout", "10060", "08001", "HYT00", "Login timeout", "TCP Provider")
        )
        if attempt < 7 and transient:
            time.sleep(10 + attempt * 10)
            continue
        break
sys.stderr.write(last[:400])
sys.exit(1)
PYEOF

      # Same signature as before: execute_sql <database> <query> <description>.
      execute_sql() {
        local database=$1 query=$2 description=$3 err
        echo "  $description..."
        if [ -z "$SQL_DRIVER" ]; then
          echo "    ⚠️  No SQL driver available - skipped"
          return 1
        fi
        ACCESS_TOKEN=$(az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>/dev/null)
        if WIV_SQL_TOKEN="$ACCESS_TOKEN" WIV_SQL_DRIVER="$SQL_DRIVER" \
            python3 "$SQL_HELPER" "$SQL_SERVER" "$database" <<< "$query" >/dev/null 2>/tmp/wiv_sql_err; then
          echo "    ✅ Success"
          return 0
        fi
        err=$(tr -d '\n' < /tmp/wiv_sql_err 2>/dev/null | cut -c1-200)
        echo "    ⚠️  Failed: ${err:-unknown error}"
        return 1
      }

      # First query resumes the serverless pool; the helper already retries on cold start.
      if [ -n "$SQL_DRIVER" ]; then
        echo "  Warming up serverless SQL endpoint (first query resumes the pool)..."
        if WIV_SQL_TOKEN="$ACCESS_TOKEN" WIV_SQL_DRIVER="$SQL_DRIVER" \
            python3 "$SQL_HELPER" "$SQL_SERVER" "master" <<< "SELECT 1" >/dev/null 2>&1; then
          echo "    ✅ Endpoint responsive"
        else
          echo "    ⏳ Endpoint still resuming - continuing (each statement retries)"
        fi
      fi

      execute_sql "master" \
        "IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = '${BILLING_DATABASE}') CREATE DATABASE ${BILLING_DATABASE}" \
        "Creating database ${BILLING_DATABASE}"
      sleep 5

      # FOCUS CSVs are UTF-8; without a UTF-8 collation, VARCHAR reads raise conversion warnings.
      execute_sql "master" \
        "ALTER DATABASE ${BILLING_DATABASE} COLLATE Latin1_General_100_CI_AS_SC_UTF8" \
        "Setting UTF-8 database collation"
      sleep 3

      MASTER_KEY_PASSWORD="StrongP@ssw0rd${UNIQUE_SUFFIX}!"
      execute_sql "$BILLING_DATABASE" \
        "IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##') CREATE MASTER KEY ENCRYPTION BY PASSWORD = '${MASTER_KEY_PASSWORD}'" \
        "Creating master key"
      sleep 3

      execute_sql "$BILLING_DATABASE" \
        "IF NOT EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'WorkspaceIdentity') CREATE DATABASE SCOPED CREDENTIAL WorkspaceIdentity WITH IDENTITY = 'Managed Identity'" \
        "Creating credential"
      sleep 3

      # NOTE: the external data source is (re)created AFTER the view is dropped (below),
      # because it must always point at the CURRENT storage account. On a reused
      # workspace the BillingAnalytics DB persists, so an IF NOT EXISTS data source
      # would keep pointing at a previous run's storage -> "cannot be listed".

      execute_sql "$BILLING_DATABASE" \
        "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '${APP_DISPLAY_NAME}') CREATE USER [${APP_DISPLAY_NAME}] FROM EXTERNAL PROVIDER" \
        "Creating user for service principal"
      sleep 2

      execute_sql "$BILLING_DATABASE" "ALTER ROLE db_datareader ADD MEMBER [${APP_DISPLAY_NAME}]" "Granting db_datareader"
      execute_sql "$BILLING_DATABASE" "ALTER ROLE db_datawriter ADD MEMBER [${APP_DISPLAY_NAME}]" "Granting db_datawriter"
      execute_sql "$BILLING_DATABASE" "ALTER ROLE db_ddladmin ADD MEMBER [${APP_DISPLAY_NAME}]" "Granting db_ddladmin"
      sleep 3

      execute_sql "$BILLING_DATABASE" \
        "IF OBJECT_ID('BillingData', 'V') IS NOT NULL DROP VIEW BillingData" \
        "Dropping existing BillingData view"

      # Recreate the data source so it always points at THIS run's storage account.
      # (Drop requires no dependent views, hence after the view drop above.)
      execute_sql "$BILLING_DATABASE" \
        "IF EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'BillingStorage') DROP EXTERNAL DATA SOURCE BillingStorage" \
        "Dropping existing external data source (point at current storage)"
      sleep 2
      execute_sql "$BILLING_DATABASE" \
        "CREATE EXTERNAL DATA SOURCE BillingStorage WITH (LOCATION = 'abfss://${CONTAINER_NAME}@${STORAGE_ACCOUNT_NAME}.dfs.core.windows.net/', CREDENTIAL = WorkspaceIdentity)" \
        "Creating external data source -> ${STORAGE_ACCOUNT_NAME}"
      sleep 2

      # Actual layout: <rootFolder>/<exportName>/<daterange>/<runtimestamp>/<guid>/part_*.csv
      BILLING_BULK_PATH="${ROOT_FOLDER}/${EXPORT_NAME}/*/*/*/*.csv"
      BILLING_VIEW_SQL="CREATE VIEW BillingData AS
SELECT *
FROM OPENROWSET(
    BULK '${BILLING_BULK_PATH}',
    DATA_SOURCE = 'BillingStorage',
    FORMAT = 'CSV',
    PARSER_VERSION = '2.0',
    HEADER_ROW = TRUE
)
WITH (
    BilledCost VARCHAR(50),
    BillingAccountId VARCHAR(256),
    BillingAccountName VARCHAR(256),
    BillingAccountType VARCHAR(256),
    BillingCurrency VARCHAR(16),
    BillingPeriodEnd VARCHAR(50),
    BillingPeriodStart VARCHAR(50),
    ChargeCategory VARCHAR(256),
    ChargeClass VARCHAR(50),
    ChargeDescription VARCHAR(512),
    ChargeFrequency VARCHAR(64),
    ChargePeriodEnd VARCHAR(50),
    ChargePeriodStart VARCHAR(50),
    CommitmentDiscountCategory VARCHAR(50),
    CommitmentDiscountId VARCHAR(256),
    CommitmentDiscountName VARCHAR(256),
    CommitmentDiscountStatus VARCHAR(256),
    CommitmentDiscountType VARCHAR(256),
    ConsumedQuantity VARCHAR(50),
    ConsumedUnit VARCHAR(64),
    ContractedCost VARCHAR(50),
    ContractedUnitPrice VARCHAR(50),
    EffectiveCost VARCHAR(50),
    InvoiceIssuerName VARCHAR(256),
    ListCost VARCHAR(50),
    ListUnitPrice VARCHAR(50),
    PricingCategory VARCHAR(256),
    PricingQuantity VARCHAR(50),
    PricingUnit VARCHAR(64),
    ProviderName VARCHAR(256),
    PublisherName VARCHAR(256),
    RegionId VARCHAR(256),
    RegionName VARCHAR(256),
    ResourceId VARCHAR(512),
    ResourceName VARCHAR(512),
    ResourceType VARCHAR(256),
    ServiceCategory VARCHAR(256),
    ServiceName VARCHAR(256),
    SkuId VARCHAR(256),
    SkuPriceId VARCHAR(256),
    SubAccountId VARCHAR(256),
    SubAccountName VARCHAR(256),
    SubAccountType VARCHAR(256),
    Tags VARCHAR(4000),
    x_AccountId VARCHAR(256),
    x_AccountName VARCHAR(256),
    x_AccountOwnerId VARCHAR(256),
    x_BilledCostInUsd VARCHAR(50),
    x_BilledUnitPrice VARCHAR(50),
    x_BillingAccountId VARCHAR(256),
    x_BillingAccountName VARCHAR(256),
    x_BillingExchangeRate VARCHAR(50),
    x_BillingExchangeRateDate VARCHAR(50),
    x_BillingProfileId VARCHAR(256),
    x_BillingProfileName VARCHAR(256),
    x_ContractedCostInUsd VARCHAR(50),
    x_CostAllocationRuleName VARCHAR(256),
    x_CostCenter VARCHAR(256),
    x_CustomerId VARCHAR(256),
    x_CustomerName VARCHAR(256),
    x_EffectiveCostInUsd VARCHAR(50),
    x_EffectiveUnitPrice VARCHAR(50),
    x_InvoiceId VARCHAR(256),
    x_InvoiceIssuerId VARCHAR(256),
    x_InvoiceSectionId VARCHAR(256),
    x_InvoiceSectionName VARCHAR(256),
    x_ListCostInUsd VARCHAR(50),
    x_PartnerCreditApplied VARCHAR(50),
    x_PartnerCreditRate VARCHAR(50),
    x_PricingBlockSize VARCHAR(50),
    x_PricingCurrency VARCHAR(16),
    x_PricingSubcategory VARCHAR(256),
    x_PricingUnitDescription VARCHAR(512),
    x_PublisherCategory VARCHAR(256),
    x_PublisherId VARCHAR(256),
    x_ResellerId VARCHAR(256),
    x_ResellerName VARCHAR(256),
    x_ResourceGroupName VARCHAR(256),
    x_ResourceType VARCHAR(256),
    x_ServicePeriodEnd VARCHAR(50),
    x_ServicePeriodStart VARCHAR(50),
    x_SkuDescription VARCHAR(512),
    x_SkuDetails VARCHAR(1024),
    x_SkuIsCreditEligible VARCHAR(16),
    x_SkuMeterCategory VARCHAR(256),
    x_SkuMeterId VARCHAR(256),
    x_SkuMeterName VARCHAR(512),
    x_SkuMeterSubcategory VARCHAR(256),
    x_SkuOfferId VARCHAR(256),
    x_SkuOrderId VARCHAR(256),
    x_SkuOrderName VARCHAR(256),
    x_SkuPartNumber VARCHAR(256),
    x_SkuRegion VARCHAR(256),
    x_SkuServiceFamily VARCHAR(256),
    x_SkuTerm VARCHAR(256),
    x_SkuTier VARCHAR(256)
) AS BillingExport"

      if execute_sql "$BILLING_DATABASE" "$BILLING_VIEW_SQL" "Creating FOCUS BillingData view"; then
        DATABASE_CREATED=true
      fi

      # Storage data-plane RBAC for the Synapse identity can take several minutes to
      # propagate to the serverless endpoint. CREATE VIEW does NOT validate data access,
      # so the first real SELECT (here or from the backend) is what fails. Warm it up and
      # verify BillingData is actually readable before we finish, so reuse runs don't
      # leave a view that errors with "cannot be listed" on first query.
      if [ "$DATABASE_CREATED" = "true" ]; then
        # A freshly-granted Storage Blob Data Reader is NOT effective immediately on the
        # serverless endpoint: on-demand SQL caches the earlier "denied" result and keeps
        # returning "cannot be listed" until that negative-auth cache expires (~10 min).
        # RBAC + firewall are already correct by here, so we wait out the cache (up to
        # ~13 min) and verify a real read succeeds before declaring success.
        echo "  Verifying BillingData is readable (waiting out serverless auth cache, up to ~13 min)..."
        echo "  (RBAC + firewall are already set; this is just propagation - it is safe to leave running.)"
        BILLING_READABLE="false"
        for _vtry in $(seq 1 18); do
          if execute_sql "$BILLING_DATABASE" "SELECT TOP 1 1 AS ok FROM BillingData" "Validation read (${_vtry}/18)"; then
            BILLING_READABLE="true"
            echo "  ✅ BillingData is queryable"
            break
          fi
          sleep 45
        done
        if [ "$BILLING_READABLE" != "true" ]; then
          echo "  ⚠️  BillingData still not readable after ~13 min. Remaining causes:"
          echo "       - Serverless auth cache not cleared yet (wait a few more min, retry once)"
          echo "       - First export files have not landed yet (can take 5-30 min)"
          echo "     Setup is otherwise complete - re-run 'SELECT TOP 10 * FROM BillingData' shortly."
        fi
      fi
    else
      echo "   ⚠️  Could not obtain database access token - Synapse SQL setup skipped"
    fi

    cat > synapse_config.py <<EOF
# Auto-generated Synapse configuration for Wiv billing analytics
SYNAPSE_CONFIG = {
    'tenant_id': '${TENANT_ID}',
    'client_id': '${APP_ID}',
    'client_secret': '${CLIENT_SECRET}',
    'workspace_name': '${SYNAPSE_WORKSPACE}',
    'database_name': '${BILLING_DATABASE}',
    'storage_account': '${STORAGE_ACCOUNT_NAME}',
    'container': '${CONTAINER_NAME}',
    'export_path': '${ROOT_FOLDER}',
    'export_name': '${EXPORT_NAME}',
    'resource_group': '${RESOURCE_GROUP}',
    'subscription_id': '${APP_SUBSCRIPTION_ID}',
    'billing_account_name': '${BILLING_ACCOUNT_NAME}',
    'export_format': 'FOCUS'
}
EOF
    echo "   ✅ synapse_config.py written"

    if [ "$DATABASE_CREATED" = "true" ]; then
      SYNAPSE_DEPLOYED="y"
      echo "   ✅ Synapse SQL setup complete (first export files may take 5-30 min to appear)"
    else
      echo "   ⚠️  Synapse workspace created but SQL setup incomplete - re-run or check permissions"
    fi
  else
    echo "   ⚠️  Synapse workspace not available - skipping SQL setup"
  fi

  fi
else
  echo ""
  echo "⏭️  Skipping billing export + Synapse (no billing account selected)"
fi

# =====================================================================
# OPTIONAL: org-level metrics via MANAGEMENT-GROUP scope (not per-sub)
# =====================================================================
echo ""
echo "📈 Metrics (Monitoring Reader) - org-level only"
echo "   Azure Monitor has no billing-account scope. The org-level (non per-sub)"
echo "   path is a management-group assignment, which inherits to every"
echo "   subscription under that group."
echo ""

MG_ID=""
MG_LABEL="(skipped)"

# List management groups the caller can see.
echo "   Existing management groups:"
MG_TABLE=$(az account management-group list --query "[].{Name:name, DisplayName:displayName}" -o table 2>/dev/null)

if [ -n "$MG_TABLE" ] && [ "$(echo "$MG_TABLE" | wc -l)" -gt 2 ]; then
  echo "$MG_TABLE" | sed 's/^/     /'
  echo ""
  read -p "   Paste a management group Name to use (or Enter to skip metrics): " MG_ID
else
  echo "     (none found in this tenant)"
  echo ""
  read -p "   No management group exists. Create one now to enable org-level metrics? (y/n): " MK_MG
  if [[ "$MK_MG" =~ ^[Yy]$ ]]; then
    read -p "   New management group ID (no spaces, e.g. wiv-finops): " MG_ID
    read -p "   Display name [$MG_ID]: " MG_DISPLAY
    MG_DISPLAY="${MG_DISPLAY:-$MG_ID}"
    echo "   Creating management group '$MG_ID' (under tenant root)..."
    if az account management-group create --name "$MG_ID" --display-name "$MG_DISPLAY" --only-show-errors >/dev/null 2>&1; then
      echo "   ✅ Created. NOTE: a new MG is empty - Monitoring Reader inherits to"
      echo "      nothing until subscriptions are moved into it."
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
      echo "   ⚠️  Could not create management group (needs Microsoft.Management/managementGroups/write). Skipping metrics."
      MG_ID=""
    fi
  fi
fi

if [ -n "$MG_ID" ]; then
  echo "   Assigning Monitoring Reader at management group '$MG_ID'..."
  assign_role_with_retry "$SP_OBJECT_ID" "Monitoring Reader" "/providers/Microsoft.Management/managementGroups/${MG_ID}" \
    && MG_LABEL="$MG_ID (inherits to all subs under it)"
fi

# =====================================================================
# OPTIONAL: Microsoft Graph application permission
# =====================================================================
echo ""
read -p "Grant Microsoft Graph Directory.Read.All (application permission)? (y/n): " GRANT_PERMS
if [[ "$GRANT_PERMS" =~ ^[Yy]$ ]]; then
  echo "📘 Adding Directory.Read.All (Role) and consenting..."
  az ad app permission add \
    --id "$APP_ID" \
    --api 00000003-0000-0000-c000-000000000000 \
    --api-permissions 7ab1d382-f21e-4acd-a863-ba3e13f7da61=Role \
    --only-show-errors
  if az ad app permission admin-consent --id "$APP_ID" 2>/dev/null; then
    echo "✅ Admin consent granted."
  else
    echo "⚠️  Admin consent failed - grant manually (App registrations > API permissions)."
  fi
else
  echo "🚫 Skipping Microsoft Graph permission."
fi

# --- Final output ---
echo ""
echo "✅ Onboarding Complete (org-level)"
echo "--------------------------------------"
echo "📄 Tenant ID:        $TENANT_ID"
echo "📄 App (Client) ID:  $APP_ID"
echo "📄 SP Object ID:     $SP_OBJECT_ID"
if [ -n "$BILLING_ACCOUNT_NAME" ]; then
  echo "📄 Cost scope:       billingAccounts/$BILLING_ACCOUNT_NAME (${AGREEMENT:-unknown})"
fi
echo "📄 Metrics scope:    $MG_LABEL"
if [ "$SYNAPSE_DEPLOYED" = "y" ]; then
  echo ""
  echo "📊 Billing export + Synapse:"
  echo "📄 Resource group:   $RESOURCE_GROUP"
  echo "📄 Storage account:  $STORAGE_ACCOUNT_NAME"
  echo "📄 Container:        $CONTAINER_NAME"
  echo "📄 Export name:      $EXPORT_NAME (FOCUS, daily, billing-account scope - all subscriptions)"
  echo "📄 Export path:      $ROOT_FOLDER/${EXPORT_NAME}/"
  echo "📄 Synapse workspace: $SYNAPSE_WORKSPACE"
  [ -n "$SYNAPSE_REGION" ] && echo "📄 Synapse region:    $SYNAPSE_REGION"
  echo "📄 Synapse endpoint: ${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net"
  echo "📄 Database:         $BILLING_DATABASE (view: BillingData)"
  echo "📄 Config file:      synapse_config.py"
fi
if [ -n "$SYNAPSE_WORKSPACE" ] && az synapse workspace show --name "$SYNAPSE_WORKSPACE" --resource-group "$RESOURCE_GROUP" --subscription "$APP_SUBSCRIPTION_ID" >/dev/null 2>&1; then
  export SYNAPSE_WORKSPACE
  export SYNAPSE_SERVERLESS_ENDPOINT="${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net"
  echo ""
  echo "📄 Synapse workspace name: $SYNAPSE_WORKSPACE"
  echo "📄 Synapse SQL endpoint:   ${SYNAPSE_WORKSPACE}-ondemand.sql.azuresynapse.net"
  printf 'SYNAPSE_WORKSPACE=%s\nSYNAPSE_SERVERLESS_ENDPOINT=%s-ondemand.sql.azuresynapse.net\n' \
    "$SYNAPSE_WORKSPACE" "$SYNAPSE_WORKSPACE" > synapse_workspace.env
  echo "   (also written to synapse_workspace.env and exported to this shell)"
fi

echo ""
if [ -n "$CLIENT_SECRET" ]; then
  echo "🔐 CLIENT SECRET (sensitive - store in your secret manager, do not commit):"
  echo "    $CLIENT_SECRET"
else
  echo "🔐 CLIENT SECRET: not regenerated (existing service principal)."
  echo "    Reuse the secret saved during the first onboarding."
fi