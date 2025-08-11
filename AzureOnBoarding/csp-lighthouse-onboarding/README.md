# CSP Azure Lighthouse Mass Onboarding

This solution enables CSP (Cloud Solution Provider) partners to mass onboard all their customers to Azure Lighthouse for centralized monitoring and cost management - **without any customer involvement**.

## 🎯 What This Does

- Creates a single service principal in your CSP tenant
- Uses AOBO (Admin On Behalf Of) privileges to automatically deploy Lighthouse
- Grants your service principal **limited** permissions (Cost Management Reader + Monitoring Reader)
- Processes all customers in parallel for speed
- No customer action required - fully automated

## 📋 Prerequisites

1. **CSP Partner Status**: You must be a Microsoft CSP partner with active customer relationships
2. **Azure CLI**: Install [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
3. **AOBO Access**: CSP admin privileges to access customer tenants
4. **Service Principal**: An app registration in your CSP tenant (created by our scripts)

## 🚀 Quick Start

### Step 1: Get Your Service Principal IDs

Run this in your CSP/managing tenant:

```bash
cd csp-lighthouse-onboarding
chmod +x get-app-ids.sh
./get-app-ids.sh

# This will:
# - Find or create your app registration
# - Get the Service Principal Object ID
# - Save configuration to lighthouse-config.env
```

### Step 2: Prepare Customer List

Create a `customers.txt` file with your customers:

```bash
# Format: CustomerName[TAB]TenantID
Contoso Corp	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
Fabrikam Inc	bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
```

**To get customer list from Partner Center:**
```powershell
# Using Partner Center PowerShell
Connect-PartnerCenter
Get-PartnerCustomer | Select-Object Name, TenantId | Export-Csv customers.csv
```

### Step 3: Run Mass Onboarding

```bash
chmod +x parallel-mass-onboard.sh

# Test with dry run first
./parallel-mass-onboard.sh --dry-run

# Run actual deployment
./parallel-mass-onboard.sh

# With options:
./parallel-mass-onboard.sh --batch-size 20  # Process 20 customers in parallel
./parallel-mass-onboard.sh --filter "Production"  # Only customers with "Production" in name
```

## 📁 File Structure

```
csp-lighthouse-onboarding/
├── get-app-ids.sh              # Fetches service principal IDs
├── parallel-mass-onboard.sh    # Mass deployment script
├── lighthouse-template.json    # ARM template for Lighthouse
├── parameters.json             # Template parameters (template)
├── role-definitions.json       # Reference for Azure role IDs
├── customers-sample.txt        # Sample customer file format
├── .gitignore                  # Excludes sensitive files
└── README.md                   # This file
```

## 🔧 Configuration

### Environment Variables (lighthouse-config.env)

After running `get-app-ids.sh`, you'll have:

```bash
CSP_TENANT_ID="your-csp-tenant-id"
CSP_APP_ID="your-app-client-id"
CSP_SP_OBJECT_ID="your-sp-object-id"  # Critical for Lighthouse
CSP_APP_NAME="wiv_account"
```

### Customizing Permissions

Edit `lighthouse-template.json` to modify permissions. Default roles:

| Role | ID | Purpose |
|------|-----|---------|
| Cost Management Reader | 72fafb9e-0641-4937-9268-a91bfd8191a3 | Read cost and billing data |
| Monitoring Reader | 43d0d8ad-25c7-4714-9337-8ba259a9fe05 | Read metrics and logs |

See `role-definitions.json` for more built-in roles.

## 🔄 How It Works

1. **Authentication**: Script uses your CSP AOBO privileges
2. **Parallel Processing**: Deploys to multiple customers simultaneously
3. **Lighthouse Deployment**: Creates delegation in each customer subscription
4. **Logging**: Tracks success/failure for each customer
5. **Result**: Your single SP can access all customer resources

## 📊 Monitoring Progress

During deployment:
- Real-time console output shows progress
- `logs/onboarding_status_TIMESTAMP.csv` - Detailed status
- `logs/onboarding_errors_TIMESTAMP.log` - Error details

View results:
```bash
# Show status in table format
cat logs/onboarding_status_*.csv | column -t -s ','

# Check for errors
cat logs/onboarding_errors_*.log
```

## 🔍 Verification

After deployment, verify access:

```bash
# List all accessible subscriptions
az account list --all --output table

# Test access to specific customer
az account set --subscription "customer-subscription-id"
az cost management query --type ActualCost --timeframe MonthToDate
```

In Azure Portal:
1. Go to Azure Lighthouse > Service providers
2. You should see all delegations
3. Switch context to access customer resources

## ⚠️ Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| "Not logged in to Azure" | Run `az login` first |
| "AOBO access failed" | Verify CSP relationship is active |
| "No subscriptions found" | Customer may not have Azure subscriptions |
| "Deployment failed" | Check if Lighthouse is already configured |

### Retry Failed Deployments

```bash
# Extract failed customers
grep FAILED logs/onboarding_status_*.csv | cut -d',' -f3 > failed-tenants.txt

# Create new customers.txt with only failed ones
# Then rerun the deployment
```

## 🔒 Security Considerations

1. **Minimal Permissions**: Only Cost and Monitoring Reader (no write access)
2. **Audit Trail**: All access is logged in both tenants
3. **Revocable**: Customers can remove delegation anytime
4. **No Credentials**: No secrets stored in customer tenants

## 📈 Scaling

| Customers | Estimated Time | Recommended Batch Size |
|-----------|---------------|------------------------|
| 1-10 | 2-5 minutes | 5 |
| 10-50 | 5-10 minutes | 10 |
| 50-100 | 10-20 minutes | 15 |
| 100-500 | 30-60 minutes | 20 |
| 500+ | 1-2 hours | 25 |

## 🤝 CSP vs Direct Comparison

| Aspect | CSP with AOBO + Lighthouse | Direct Customer Deployment |
|--------|---------------------------|---------------------------|
| Customer Action | None | Must run deployment |
| Deployment Speed | Minutes (automated) | Days/weeks (coordination) |
| Scalability | Excellent (parallel) | Poor (manual) |
| Credential Management | Single SP | Multiple credentials |
| Maintenance | Centralized | Per-customer |

## 📝 Advanced Usage

### Exclude Specific Customers

```bash
# Create exclude list
echo "tenant-id-to-exclude" > exclude-list.txt

# Run with exclusions
./parallel-mass-onboard.sh --exclude-file exclude-list.txt
```

### Custom Role Assignments

Modify the `authorizations` array in `lighthouse-template.json`:

```json
{
    "principalId": "your-sp-object-id",
    "roleDefinitionId": "custom-role-id",
    "principalIdDisplayName": "Display Name"
}
```

### Integration with CI/CD

```yaml
# Azure DevOps Pipeline example
- script: |
    cd csp-lighthouse-onboarding
    ./get-app-ids.sh
    ./parallel-mass-onboard.sh --batch-size 20
  displayName: 'Deploy Lighthouse to all CSP customers'
```

## 📚 Additional Resources

- [Azure Lighthouse Documentation](https://docs.microsoft.com/en-us/azure/lighthouse/)
- [CSP Partner Documentation](https://docs.microsoft.com/en-us/partner-center/)
- [Azure RBAC Roles](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles)

## 🆘 Support

For issues or questions:
1. Check the error logs in `logs/` directory
2. Verify CSP relationship status in Partner Center
3. Ensure Azure Lighthouse is available in customer regions

## 📄 License

This solution is provided as-is for CSP partners to streamline Azure Lighthouse onboarding.

---

**Note**: This solution uses CSP AOBO privileges responsibly to deploy minimal required permissions via Azure Lighthouse, ensuring security while eliminating customer friction in the onboarding process.