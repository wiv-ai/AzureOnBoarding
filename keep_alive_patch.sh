#!/bin/bash

# This patch adds keep-alive messages to prevent Azure Cloud Shell timeout

cat << 'EOF'
The script needs to be updated with keep-alive messages to prevent Azure Cloud Shell from timing out.

Add this function at the beginning of the script after the tool installation section:

# ===========================
# KEEP-ALIVE FUNCTION FOR CLOUD SHELL
# ===========================
keep_alive_wait() {
    local duration=$1
    local message=$2
    local interval=5
    local elapsed=0
    
    while [ $elapsed -lt $duration ]; do
        echo "   ⏳ ${message}... ($elapsed seconds elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
}

Then replace these lines:

1. Replace:
   sleep 30
   With:
   keep_alive_wait 30 "Waiting for workspace"

2. Replace:
   echo "⏳ Waiting for Synapse workspace to be fully operational..."
   sleep 30
   With:
   echo "⏳ Waiting for Synapse workspace to be fully operational..."
   keep_alive_wait 30 "Workspace initializing"

3. Replace:
   echo "⏳ Waiting 30 seconds for firewall rules to fully propagate..."
   sleep 30
   With:
   echo "⏳ Waiting 30 seconds for firewall rules to fully propagate..."
   keep_alive_wait 30 "Firewall rules propagating"

4. Replace the long wait section:
   echo "   This takes 2-3 minutes for new workspaces..."
   sleep 60
   echo "   Still initializing... (1 minute elapsed)"
   sleep 60
   echo "   Almost ready... (2 minutes elapsed)"
   sleep 30
   With:
   echo "   This takes 2-3 minutes for new workspaces..."
   keep_alive_wait 150 "Synapse initializing"

5. For the az synapse workspace wait command, add:
   # Keep Cloud Shell active during long wait
   (while true; do echo "   ⏳ Still waiting for workspace creation..."; sleep 20; done) &
   KEEPALIVE_PID=$!
   az synapse workspace wait --resource-group "$BILLING_RG" --workspace-name "$SYNAPSE_WORKSPACE" --created
   kill $KEEPALIVE_PID 2>/dev/null

This will prevent Azure Cloud Shell from timing out during long operations.
EOF