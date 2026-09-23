# Azure onboarding (FOCUS billing export → Blob)

Manual / Cloud Shell onboarding for Azure cost integrations. Provisions the same **direct blob** billing path as Wiv product onboarding (Generate Integration Link and in-app keyless installer).

Synapse is **not** part of this flow. Legacy Synapse scripts remain in the repo for older integrations only.

## What the script sets up

| Piece | Detail |
|-------|--------|
| **App registration** | `wiv_account` service principal (client-secret auth for manual installs) |
| **Billing account roles** | Enrollment Reader (EA) or Billing account reader (MCA / partner) |
| **Per-subscription ARM roles** | Reader, Monitoring Reader, Cost Management Reader on every billed subscription (`billingSubscriptions` API). **POC:** you can grant those roles only on subscriptions you pick, and skip the management group. |
| **FOCUS export** | Daily Parquet/Snappy at billing-account scope → `rg-wiv` storage |
| **Export identity** | System-assigned managed identity on the export (required when storage has `allowSharedKeyAccess=false`) |
| **Blob access** | Storage Blob Data Reader on the export storage account for the SP |
| **Management group (optional)** | Reader + Monitoring Reader at a management group (inherits to subs under the MG, including new ones you place there) |

## Prerequisites

- Azure CLI (`az`), `curl`, `python3`
- Logged in as a tenant/billing admin with rights to create app registrations, billing exports, and role assignments
- A billing account visible to the login (EA, MCA, or CSP partner MCA)

## Quick start (Cloud Shell)

1. Clone and open Cloud Shell profile (or run locally after `az login`):

```bash
git clone https://github.com/wiv-ai/AzureOnBoarding.git
cd AzureOnBoarding
```

2. Run the onboarding script:

```bash
bash .cloudshell/startup.sh
```

3. Follow prompts:

- Pick the **host subscription** (where `rg-wiv` and billing storage live)
- Paste the **billing account name** from `az billing account list`
- Optionally answer **y** to the **POC** prompt to grant Reader / Monitoring Reader only on chosen subscription IDs (skips all-billed ARM roles and the management-group step)
- Otherwise optionally select a **management group** from the numbered list (or **Skip** — new subscriptions will not inherit MG-scoped access)

4. Save the output **client secret** (only generated for a **new** `wiv_account` app). Store it in your secret manager; do not commit it.

5. In Wiv, create or verify an Azure integration with:

The script prints a ready-to-paste JSON secret at the end, including host `subscription_id`, storage resource ID, container, root folder, and export name. Shape:

```json
{
  "auth_method": "client_secret",
  "tenant_id": "<Azure AD tenant>",
  "app_id": "<from script output>",
  "client_secret": "<from script output>",
  "sp_object_id": "<from script output>",
  "billing_account_name": "<selected billing account>",
  "billing_query_backend": "blob",
  "billing_storage_account": "<wivbill… from script>",
  "billing_storage_resource_id": "<from script output>",
  "billing_container": "billing-exports",
  "billing_root_folder": "billing-data",
  "billing_export_name": "WivFocusDailyExport",
  "subscription_id": "<host subscription>"
}
```

For **keyless** (`federated_workload`) integrations, use **Generate Integration Link** or in-app onboarding instead — the script is the client-secret / manual operator path.

## Architecture (blob-only)

```
Billing account (EA / MCA / partner)
        │
        ▼
  FOCUS daily export (Parquet)
        │
        ▼
  Storage account (rg-wiv / wivbill*)
  allowSharedKeyAccess=false
        │
        ▼
  Wiv queries blobs directly
  (billing_query_backend: blob)
```

## Idempotency and re-runs

Safe to re-run. The script:

- Reuses an existing `wiv_account` SP (does **not** rotate its secret)
- Reuses an existing FOCUS export when destination storage is valid
- Patches billing storage security (`allowSharedKeyAccess=false`) when needed
- Skips role assignments that already exist

## Product onboarding (recommended)

| Path | Auth | Same provisioning engine? |
|------|------|-----------------------------|
| In-app Azure wizard | `federated_workload` | Yes |
| Generate Integration Link | `federated_workload` | Yes |
| This Cloud Shell script | `client_secret` | Same resources; manual steps |

Backend docs (in `wiv-ai/backend`):

- `wf_operations/src/integrations/azure/AZURE_KEYLESS_INSTALLATION_API.md`
- `wf_operations/src/integrations/azure/AZURE_ONBOARD_LINK_API.md`
- `wf_operations/src/integrations/azure/AZURE_PLATFORM_HANDOFF.md`

## Legacy Synapse scripts (deprecated)

These are **not** used for new Wiv integrations:

| File | Notes |
|------|--------|
| `startup_with_billing_synapse.sh` | Old all-in-one Synapse + export setup |
| `csp_billing_synapse_setup.sh` | CSP-focused Synapse variant |
| `synapse_remote_query_client.py` | Query helper for legacy Synapse workspaces |
| `diagnose_synapse_auth.py` | Synapse auth diagnostics |

Existing integrations that still have `workspace_name` in the secret can use Synapse as a runtime fallback until migrated to blob-only.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|----------------|-----|
| Export create fails with shared-key / auth error | Storage has shared key disabled but export has no managed identity | Re-run script (adds `identity: SystemAssigned` on export) or recreate export |
| Subscription missing in Wiv after onboard | SP lacks Reader on that sub | Script grants via `billingSubscriptions`; re-run or assign roles manually |
| `AADSTS700016` in workflows | App registration deleted or wrong `tenant_id` | Re-onboard; do not bulk-delete `wiv_account-*` apps still referenced by integrations |
| Billing export 403 | Billing role not propagated | Wait a few minutes; confirm Enrollment Reader / Billing account reader on the SP |
| No data in Wiv yet | First export run pending | FOCUS export can take 5–30 minutes after creation |

## License

Part of the wiv.ai Azure onboarding suite.
