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
else
  echo "✅ Service principal exists. App ID: $APP_ID"
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
echo ""
echo "🔑 Creating client secret (2y expiry)..."
if date --version >/dev/null 2>&1; then
  END_DATE=$(date -d "+2 years" +"%Y-%m-%d")
else
  END_DATE=$(date -v +2y +"%Y-%m-%d")
fi
CLIENT_SECRET=$(az ad app credential reset --id "$APP_ID" --end-date "$END_DATE" --query password -o tsv)
[ -z "$CLIENT_SECRET" ] && { echo "❌ Failed to create client secret."; exit 1; }

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

# =====================================================================
# OPTIONAL: org-level metrics via MANAGEMENT-GROUP scope (not per-sub)
# =====================================================================
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
echo ""
echo "🔐 CLIENT SECRET (sensitive - store in your secret manager, do not commit):"
echo "    $CLIENT_SECRET"