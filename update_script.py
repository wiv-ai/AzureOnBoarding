#!/usr/bin/env python3

# Read the file
with open('startup_with_billing_synapse.sh', 'r') as f:
    content = f.read()

# Define the old section to replace
old_section = '''# Assign roles to all subscriptions
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
done'''

# Define the new section
new_section = '''# Assign roles to the current subscription only
echo ""
echo "🔒 Assigning roles to subscription: $APP_SUBSCRIPTION_ID"

# Assign Cost Management Reader role
echo "  - Assigning Cost Management Reader..."
az role assignment create --assignee "$APP_ID" --role "Cost Management Reader" --scope "/subscriptions/$APP_SUBSCRIPTION_ID" --only-show-errors

# Assign Monitoring Reader role
echo "  - Assigning Monitoring Reader..."
az role assignment create --assignee "$APP_ID" --role "Monitoring Reader" --scope "/subscriptions/$APP_SUBSCRIPTION_ID" --only-show-errors

# Assign Storage Blob Data Contributor role for billing exports
echo "  - Assigning Storage Blob Data Contributor..."
az role assignment create --assignee "$APP_ID" --role "Storage Blob Data Contributor" --scope "/subscriptions/$APP_SUBSCRIPTION_ID" --only-show-errors

# Assign Contributor role for Synapse workspace management
echo "  - Assigning Contributor role for Synapse management..."
az role assignment create --assignee "$APP_ID" --role "Contributor" --scope "/subscriptions/$APP_SUBSCRIPTION_ID" --only-show-errors

echo "  ✅ Done with subscription: $APP_SUBSCRIPTION_ID"'''

# Replace the content
new_content = content.replace(old_section, new_section)

# Write back
with open('startup_with_billing_synapse.sh', 'w') as f:
    f.write(new_content)

print("File updated successfully!")
