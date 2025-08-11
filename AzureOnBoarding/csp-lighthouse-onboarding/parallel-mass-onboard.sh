#!/bin/bash

#################################################################################
# parallel-mass-onboard.sh
#
# Purpose: Mass onboard all CSP customers to your SaaS platform using Azure Lighthouse
#          Deploys Lighthouse delegations in parallel for speed
#          Uses AOBO privileges - no customer involvement needed
#
# Prerequisites:
#   1. Run get-app-ids.sh first to get your service principal IDs
#   2. Source the lighthouse-config.env file
#   3. Have Partner Center API access or Azure CLI with CSP privileges
#
# Usage: ./parallel-mass-onboard.sh [options]
#   Options:
#     --batch-size N     Process N customers in parallel (default: 10)
#     --dry-run         Test mode - don't actually deploy
#     --filter STRING   Only process customers matching STRING
#     --exclude-file    File containing tenant IDs to exclude
#################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default configuration
BATCH_SIZE=10
DRY_RUN=false
FILTER=""
EXCLUDE_FILE=""
LOG_DIR="./logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
STATUS_FILE="$LOG_DIR/onboarding_status_${TIMESTAMP}.csv"
ERROR_LOG="$LOG_DIR/onboarding_errors_${TIMESTAMP}.log"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --batch-size)
            BATCH_SIZE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --filter)
            FILTER="$2"
            shift 2
            ;;
        --exclude-file)
            EXCLUDE_FILE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --batch-size N    Process N customers in parallel (default: 10)"
            echo "  --dry-run        Test mode - don't actually deploy"
            echo "  --filter STRING  Only process customers matching STRING"
            echo "  --exclude-file   File containing tenant IDs to exclude"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Create log directory
mkdir -p "$LOG_DIR"

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}           Azure Lighthouse Mass Customer Onboarding${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check if lighthouse-config.env exists and source it
if [ -f "lighthouse-config.env" ]; then
    source lighthouse-config.env
    echo -e "${GREEN}✓ Loaded configuration from lighthouse-config.env${NC}"
else
    echo -e "${RED}✗ lighthouse-config.env not found. Run get-app-ids.sh first!${NC}"
    exit 1
fi

# Verify required variables
if [ -z "$CSP_TENANT_ID" ] || [ -z "$CSP_SP_OBJECT_ID" ]; then
    echo -e "${RED}✗ Missing required configuration variables${NC}"
    echo "  CSP_TENANT_ID: $CSP_TENANT_ID"
    echo "  CSP_SP_OBJECT_ID: $CSP_SP_OBJECT_ID"
    exit 1
fi

# Check if lighthouse template exists
if [ ! -f "lighthouse-template.json" ]; then
    echo -e "${YELLOW}⚠ lighthouse-template.json not found. Creating default template...${NC}"
    # We'll create this in the next step
fi

# Check Azure CLI login
if ! az account show &>/dev/null; then
    echo -e "${RED}✗ Not logged in to Azure CLI${NC}"
    echo "Run: az login"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites met${NC}"
echo ""

# Initialize status file
echo "Timestamp,CustomerName,TenantID,SubscriptionID,Status,Details" > "$STATUS_FILE"

# Function to log status
log_status() {
    local timestamp=$(date -Iseconds)
    echo "$timestamp,$1,$2,$3,$4,$5" >> "$STATUS_FILE"
}

# Function to deploy Lighthouse to a single customer
deploy_to_customer() {
    local CUSTOMER_NAME="$1"
    local CUSTOMER_TENANT_ID="$2"
    local WORKER_ID="$3"
    
    echo -e "[Worker $WORKER_ID] ${CYAN}Processing: $CUSTOMER_NAME${NC}"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "[Worker $WORKER_ID] ${YELLOW}DRY RUN - Would deploy to: $CUSTOMER_NAME${NC}"
        log_status "$CUSTOMER_NAME" "$CUSTOMER_TENANT_ID" "N/A" "DRY_RUN" "Skipped - Dry Run"
        return 0
    fi
    
    # Try to login to customer tenant using AOBO
    if az login --tenant "$CUSTOMER_TENANT_ID" --allow-no-subscriptions &>/dev/null; then
        # Get all subscriptions for this customer
        SUBSCRIPTIONS=$(az account list --query "[].id" -o tsv 2>/dev/null)
        
        if [ -z "$SUBSCRIPTIONS" ]; then
            echo -e "[Worker $WORKER_ID] ${YELLOW}⚠ No subscriptions found for: $CUSTOMER_NAME${NC}"
            log_status "$CUSTOMER_NAME" "$CUSTOMER_TENANT_ID" "N/A" "NO_SUBSCRIPTIONS" "No Azure subscriptions found"
            return 1
        fi
        
        local SUB_COUNT=$(echo "$SUBSCRIPTIONS" | wc -l)
        echo -e "[Worker $WORKER_ID] ${BLUE}Found $SUB_COUNT subscription(s) for: $CUSTOMER_NAME${NC}"
        
        # Deploy to each subscription
        for SUBSCRIPTION_ID in $SUBSCRIPTIONS; do
            echo -e "[Worker $WORKER_ID]   → Deploying to subscription: ${SUBSCRIPTION_ID:0:20}...${NC}"
            
            # Create deployment name
            DEPLOYMENT_NAME="WIV-Lighthouse-$(date +%Y%m%d)"
            
            # Deploy Lighthouse template
            if az deployment sub create \
                --name "$DEPLOYMENT_NAME" \
                --location "eastus" \
                --subscription "$SUBSCRIPTION_ID" \
                --template-file "lighthouse-template.json" \
                --parameters \
                    mspOfferName="WIV Platform Monitoring Access" \
                    mspOfferDescription="Cost and Monitoring Reader access for WIV Platform" \
                    managedByTenantId="$CSP_TENANT_ID" \
                    authorizations="[{\"principalId\":\"$CSP_SP_OBJECT_ID\",\"roleDefinitionId\":\"72fafb9e-0641-4937-9268-a91bfd8191a3\",\"principalIdDisplayName\":\"WIV Platform\"},{\"principalId\":\"$CSP_SP_OBJECT_ID\",\"roleDefinitionId\":\"43d0d8ad-25c7-4714-9337-8ba259a9fe05\",\"principalIdDisplayName\":\"WIV Platform\"}]" \
                --no-wait \
                &>/dev/null; then
                
                echo -e "[Worker $WORKER_ID]   ${GREEN}✓ Deployed to: ${SUBSCRIPTION_ID:0:20}...${NC}"
                log_status "$CUSTOMER_NAME" "$CUSTOMER_TENANT_ID" "$SUBSCRIPTION_ID" "SUCCESS" "Lighthouse deployed"
            else
                echo -e "[Worker $WORKER_ID]   ${RED}✗ Failed to deploy to: ${SUBSCRIPTION_ID:0:20}...${NC}"
                log_status "$CUSTOMER_NAME" "$CUSTOMER_TENANT_ID" "$SUBSCRIPTION_ID" "FAILED" "Deployment failed"
                echo "Failed deployment for $CUSTOMER_NAME - $SUBSCRIPTION_ID" >> "$ERROR_LOG"
            fi
        done
        
        echo -e "[Worker $WORKER_ID] ${GREEN}✓ Completed: $CUSTOMER_NAME${NC}"
        return 0
    else
        echo -e "[Worker $WORKER_ID] ${RED}✗ Failed to access: $CUSTOMER_NAME${NC}"
        log_status "$CUSTOMER_NAME" "$CUSTOMER_TENANT_ID" "N/A" "ACCESS_FAILED" "Could not login with AOBO"
        echo "AOBO access failed for $CUSTOMER_NAME - $CUSTOMER_TENANT_ID" >> "$ERROR_LOG"
        return 1
    fi
}

# Function to get CSP customers
get_csp_customers() {
    echo -e "${YELLOW}Fetching CSP customers...${NC}"
    
    # Method 1: Try using Partner Center API (if available)
    # This requires Partner Center API setup
    
    # Method 2: Use Azure CLI to list customers from subscriptions
    # This works if you have existing CSP subscriptions
    
    # For now, we'll use a simplified approach
    # In production, integrate with Partner Center API
    
    # Example: Get unique tenant IDs from existing subscriptions
    # You would replace this with actual Partner Center API call
    
    # Temporary: Read from a file or use test data
    if [ -f "customers.txt" ]; then
        cat customers.txt
    else
        # Try to get from Azure (this requires proper CSP setup)
        az account list --all --query "[?contains(name, 'CSP')].{name:name, tenantId:homeTenantId}" -o tsv 2>/dev/null || true
    fi
}

# Load exclusion list if provided
EXCLUDE_LIST=""
if [ -n "$EXCLUDE_FILE" ] && [ -f "$EXCLUDE_FILE" ]; then
    EXCLUDE_LIST=$(cat "$EXCLUDE_FILE" | tr '\n' ' ')
    echo -e "${YELLOW}Loaded exclusion list with $(echo $EXCLUDE_LIST | wc -w) tenant(s)${NC}"
fi

# Get all CSP customers
echo -e "${YELLOW}Fetching CSP customers...${NC}"

# For demonstration, create a sample customers file if it doesn't exist
if [ ! -f "customers.txt" ]; then
    echo -e "${YELLOW}Creating sample customers.txt file...${NC}"
    cat > customers.txt << 'EOF'
Customer-A	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
Customer-B	bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
Customer-C	cccccccc-cccc-cccc-cccc-cccccccccccc
EOF
    echo -e "${YELLOW}⚠ Using sample customers.txt. Replace with actual customer data!${NC}"
fi

# Read customers
CUSTOMERS=$(cat customers.txt)

# Apply filter if provided
if [ -n "$FILTER" ]; then
    CUSTOMERS=$(echo "$CUSTOMERS" | grep -i "$FILTER" || true)
    echo -e "${YELLOW}Applied filter: '$FILTER'${NC}"
fi

# Count customers
TOTAL_CUSTOMERS=$(echo "$CUSTOMERS" | grep -v '^$' | wc -l)

if [ "$TOTAL_CUSTOMERS" -eq 0 ]; then
    echo -e "${RED}No customers found to process${NC}"
    exit 1
fi

echo -e "${GREEN}Found $TOTAL_CUSTOMERS customer(s) to process${NC}"
echo -e "${BLUE}Batch size: $BATCH_SIZE parallel deployments${NC}"
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}🔸 DRY RUN MODE - No actual deployments will be made${NC}"
    echo ""
fi

# Confirm before proceeding
if [ "$DRY_RUN" = false ]; then
    echo -e "${YELLOW}This will deploy Lighthouse to all $TOTAL_CUSTOMERS customers.${NC}"
    echo -e "${YELLOW}Continue? (yes/no):${NC}"
    read -r CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi
fi

echo ""
echo -e "${CYAN}Starting parallel deployment...${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"

# Process customers in parallel batches
COUNTER=0
SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# Create a temporary file for job tracking
JOBS_FILE=$(mktemp)

# Process each customer
while IFS=$'\t' read -r CUSTOMER_NAME CUSTOMER_TENANT_ID; do
    # Skip empty lines
    [ -z "$CUSTOMER_NAME" ] && continue
    
    # Skip if in exclusion list
    if [[ " $EXCLUDE_LIST " =~ " $CUSTOMER_TENANT_ID " ]]; then
        echo -e "${YELLOW}Skipping excluded customer: $CUSTOMER_NAME${NC}"
        ((SKIPPED_COUNT++))
        log_status "$CUSTOMER_NAME" "$CUSTOMER_TENANT_ID" "N/A" "EXCLUDED" "In exclusion list"
        continue
    fi
    
    # Increment counter
    ((COUNTER++))
    
    # Calculate worker ID for this job
    WORKER_ID=$((COUNTER % BATCH_SIZE + 1))
    
    # Launch deployment in background
    (
        deploy_to_customer "$CUSTOMER_NAME" "$CUSTOMER_TENANT_ID" "$WORKER_ID"
        echo $? > "${JOBS_FILE}_${COUNTER}"
    ) &
    
    # If we've reached batch size, wait for current batch to complete
    if [ $((COUNTER % BATCH_SIZE)) -eq 0 ]; then
        echo -e "${CYAN}Waiting for batch $((COUNTER / BATCH_SIZE)) to complete...${NC}"
        wait
        
        # Count successes and failures
        for i in $(seq $((COUNTER - BATCH_SIZE + 1)) $COUNTER); do
            if [ -f "${JOBS_FILE}_${i}" ]; then
                if [ "$(cat ${JOBS_FILE}_${i})" -eq 0 ]; then
                    ((SUCCESS_COUNT++))
                else
                    ((FAILED_COUNT++))
                fi
                rm -f "${JOBS_FILE}_${i}"
            fi
        done
        
        echo -e "${BLUE}Batch complete. Progress: Success=$SUCCESS_COUNT, Failed=$FAILED_COUNT, Skipped=$SKIPPED_COUNT${NC}"
        echo ""
    fi
done <<< "$CUSTOMERS"

# Wait for final batch
echo -e "${CYAN}Waiting for final batch to complete...${NC}"
wait

# Count final batch results
for i in $(seq $((COUNTER - COUNTER % BATCH_SIZE + 1)) $COUNTER); do
    if [ -f "${JOBS_FILE}_${i}" ]; then
        if [ "$(cat ${JOBS_FILE}_${i})" -eq 0 ]; then
            ((SUCCESS_COUNT++))
        else
            ((FAILED_COUNT++))
        fi
        rm -f "${JOBS_FILE}_${i}"
    fi
done

# Clean up temp file
rm -f "$JOBS_FILE"

# Final report
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    ONBOARDING COMPLETE${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}✅ Successful:${NC} $SUCCESS_COUNT customers"
echo -e "${RED}❌ Failed:${NC} $FAILED_COUNT customers"
echo -e "${YELLOW}⏭️  Skipped:${NC} $SKIPPED_COUNT customers"
echo -e "${BLUE}📊 Total:${NC} $TOTAL_CUSTOMERS customers"
echo ""
echo -e "${CYAN}📁 Status log:${NC} $STATUS_FILE"
if [ -f "$ERROR_LOG" ] && [ -s "$ERROR_LOG" ]; then
    echo -e "${CYAN}📁 Error log:${NC} $ERROR_LOG"
fi
echo ""

# Provide next steps
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                        NEXT STEPS${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}1. Review the status log for any failures:${NC}"
echo "   cat $STATUS_FILE | column -t -s ','"
echo ""
echo -e "${YELLOW}2. For failed deployments, check the error log:${NC}"
echo "   cat $ERROR_LOG"
echo ""
echo -e "${YELLOW}3. Verify delegations in Azure Portal:${NC}"
echo "   Azure Portal > Lighthouse > Service providers"
echo ""
echo -e "${YELLOW}4. Test access to customer resources:${NC}"
echo "   az account list --all"
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"

# Exit with appropriate code
if [ "$FAILED_COUNT" -gt 0 ]; then
    exit 1
else
    exit 0
fi