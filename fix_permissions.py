#!/usr/bin/env python3

# Read the file
with open('startup_with_billing_synapse.sh', 'r') as f:
    content = f.read()

# Remove the incorrect roles from the output
content = content.replace(
    '''echo "   - Storage Blob Data Contributor"
echo "   - Contributor"
echo "   - Synapse Administrator"
echo "   - Synapse SQL Administrator"
echo "   - Synapse Contributor"''',
    '''echo "   Note: Service principal has implicit Synapse access as workspace creator"'''
)

# Update the roles header
content = content.replace(
    'echo "🔐 Roles Assigned:"',
    'echo "🔐 Roles Assigned (Minimal Required):"'
)

# Write back
with open('startup_with_billing_synapse.sh', 'w') as f:
    f.write(content)

print("✅ Removed unnecessary role references")