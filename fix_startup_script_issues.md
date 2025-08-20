# Critical Issues in startup_with_billing_synapse.sh

## Issues Found

### 1. Syntax Error (Lines 1335-1340)
Python code is incorrectly embedded in a SQL heredoc:
```bash
-- Workspace: $SYNAPSE_WORKSPACE
    'master_key_password': '$MASTER_KEY_PASSWORD',  # This is Python!
    'sql_admin_user': '$SQL_ADMIN_USER',
    'sql_admin_password': '$SQL_ADMIN_PASSWORD'
}
```

### 2. Missing Variable Definitions
- `SUBSCRIPTION_ID` is used at line 1144 but never defined
- `STORAGE_RG` is not initialized for new storage scenario

### 3. Database Creation Issues
The database and view creation fails due to:
- Syntax error preventing proper script execution
- Multiple redundant attempts using different methods
- Python code mixed with bash heredocs

## Quick Fix

Use the existing `fix_synapse_db.sh` script:
```bash
./fix_synapse_db.sh
```

Or manually create in Synapse Studio with the SQL from `manual_fix.sql`

## Long-term Fix

The startup script needs refactoring to:
1. Remove Python code from SQL heredoc (lines 1335-1500)
2. Define missing variables properly
3. Use a single, reliable method for database creation
4. Extract embedded scripts to separate files