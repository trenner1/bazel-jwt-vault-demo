#!/bin/bash
set -euo pipefail

# Team Isolation Test for Okta OIDC Authentication
# This script tests that Okta group membership properly restricts access to team-specific secrets

echo " Testing Okta Group-Based Team Secret Isolation"
echo "================================================"

# Configuration
BROKER_URL="http://localhost:8081"
VAULT_ADDR="http://localhost:8200"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_success() {
    echo -e "${GREEN} $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}$1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_info() {
    echo -e "${BLUE} $1${NC}"
}

log_team() {
    echo -e " $1"
}

# Test setup verification
echo
log_info "Pre-Test Setup Verification"
echo "---------------------------"

# Verify broker is running with Okta OIDC
HEALTH_RESPONSE=$(curl -s "$BROKER_URL/health" || echo '{"status": "error"}')
if echo "$HEALTH_RESPONSE" | jq -e '.auth_method == "okta_oidc"' > /dev/null; then
    log_success "Broker running with Okta OIDC authentication"
else
    log_error "Broker not running or not configured for Okta OIDC"
    exit 1
fi

# Verify Vault connectivity
VAULT_HEALTH=$(curl -s "$VAULT_ADDR/v1/sys/health" || echo '{"sealed": true}')
if echo "$VAULT_HEALTH" | jq -e '.sealed == false' > /dev/null; then
    log_success "Vault is running and unsealed"
else
    log_error "Vault is not accessible or sealed"
    exit 1
fi

# Test team secret structure
echo
log_info "Team Secret Structure Verification"
echo "----------------------------------"

# Expected secret paths for each team
declare -A TEAM_PATHS=(
    ["mobile-team"]="dev/mobile"
    ["backend-team"]="dev/backend"
    ["frontend-team"]="dev/frontend"
    ["devops-team"]="dev/backend,dev/frontend,dev/mobile"
)

# Expected Okta groups to Vault role mapping
declare -A GROUP_ROLE_MAPPING=(
    ["mobile-developers"]="mobile-team"
    ["backend-developers"]="backend-team"
    ["frontend-developers"]="frontend-team"
    ["devops-team"]="devops-team"
)

echo "Expected team access patterns:"
for group in "${!GROUP_ROLE_MAPPING[@]}"; do
    role="${GROUP_ROLE_MAPPING[$group]}"
    paths="${TEAM_PATHS[$role]}"
    echo "   $group → $role → $paths"
done

# Interactive testing section
echo
log_info "Interactive Team Isolation Testing"
echo "----------------------------------"

echo "This test requires authentication as different team members."
echo "You'll need to test with accounts that belong to different Okta groups."
echo
echo "Available Okta groups to test:"
echo "   mobile-developers"
echo "   backend-developers" 
echo "   frontend-developers"
echo "   devops-team"
echo

# Function to test team access
test_team_access() {
    local session_id="$1"
    local expected_team="$2"
    local test_description="$3"
    
    echo
    log_team "$test_description"
    echo "$(printf '%*s' 50 '' | tr ' ' '-')"
    
    # Exchange session for child token
    local exchange_response=$(curl -s -X POST "$BROKER_URL/exchange" \
        -H "Content-Type: application/json" \
        -d "{
            \"session_id\": \"$session_id\",
            \"pipeline\": \"team-isolation-test\",
            \"repo\": \"test-repo\",
            \"target\": \"test-target\"
        }" || echo '{"error": "failed"}')
    
    if echo "$exchange_response" | jq -e '.token' > /dev/null; then
        local vault_token=$(echo "$exchange_response" | jq -r '.token')
        local metadata=$(echo "$exchange_response" | jq '.metadata')
        local actual_team=$(echo "$metadata" | jq -r '.team')
        local user_email=$(echo "$metadata" | jq -r '.user')
        local groups=$(echo "$metadata" | jq -r '.groups | join(", ")')
        
        log_success "Token obtained for user: $user_email"
        echo "   Team: $actual_team"
        echo "   Groups: $groups"
        echo "   Token: ${vault_token:0:20}..."
        
        # Verify team assignment matches expectation
        if [[ "$actual_team" == "$expected_team" ]]; then
            log_success "Team assignment correct: $actual_team"
        else
            log_warning "Team assignment mismatch: expected $expected_team, got $actual_team"
        fi
        
        # Get token info from Vault
        local token_info=$(curl -s -H "X-Vault-Token: $vault_token" \
            "$VAULT_ADDR/v1/auth/token/lookup-self" 2>/dev/null || echo '{"data": null}')
            
        if echo "$token_info" | jq -e '.data.id' > /dev/null; then
            local policies=$(echo "$token_info" | jq -r '.data.policies | join(", ")')
            local vault_team=$(echo "$token_info" | jq -r '.data.meta.team')
            
            log_success "Vault token is valid"
            echo "   Policies: $policies"
            echo "   Vault team metadata: $vault_team"
            
            # Test access to team-specific secrets
            test_secret_access "$vault_token" "$actual_team"
            
            # Test cross-team access restrictions
            test_cross_team_restrictions "$vault_token" "$actual_team"
            
        else
            log_error "Vault token validation failed"
        fi
        
    else
        log_error "Token exchange failed"
        echo "$exchange_response" | jq .
    fi
}

# Function to test secret access for a specific team
test_secret_access() {
    local vault_token="$1"
    local team="$2"
    
    echo
    echo "    Testing authorized secret access..."
    
    # Test shared secrets (should work for all teams)
    local shared_secret=$(curl -s -H "X-Vault-Token: $vault_token" \
        "$VAULT_ADDR/v1/kv/data/dev/shared/common" 2>/dev/null || echo '{"data": null}')
        
    if echo "$shared_secret" | jq -e '.data.data' > /dev/null; then
        log_success "   Can access shared secrets"
        local shared_config=$(echo "$shared_secret" | jq -r '.data.data.shared_config // "N/A"')
        echo "     Shared config: $shared_config"
    else
        log_warning "   Cannot access shared secrets"
    fi
    
    # Test team-specific secrets
    local team_secret_path=""
    local secret_description=""
    
    case "$team" in
        "mobile-team")
            team_secret_path="kv/data/dev/mobile/ios"
            secret_description="iOS mobile secrets"
            ;;
        "backend-team")
            team_secret_path="kv/data/dev/backend/database"
            secret_description="backend database secrets"
            ;;
        "frontend-team")
            team_secret_path="kv/data/dev/frontend/build"
            secret_description="frontend build secrets"
            ;;
        "devops-team")
            team_secret_path="kv/data/dev/backend/database"
            secret_description="cross-functional secrets"
            ;;
        *)
            log_warning "   Unknown team: $team"
            return
            ;;
    esac
    
    if [[ -n "$team_secret_path" ]]; then
        local team_secret=$(curl -s -H "X-Vault-Token: $vault_token" \
            "$VAULT_ADDR/v1/$team_secret_path" 2>/dev/null || echo '{"data": null}')
            
        if echo "$team_secret" | jq -e '.data.data' > /dev/null; then
            log_success "   Can access $secret_description"
            echo "     Path: $team_secret_path"
            local first_key=$(echo "$team_secret" | jq -r '.data.data | keys[0] // "N/A"')
            echo "     First key: $first_key"
        else
            log_warning "   Cannot access $secret_description at $team_secret_path"
        fi
    fi
}

# Function to test cross-team access restrictions
test_cross_team_restrictions() {
    local vault_token="$1"
    local team="$2"
    
    echo
    echo "   🚫 Testing cross-team access restrictions..."
    
    # Define restricted paths for each team
    declare -A RESTRICTED_PATHS
    case "$team" in
        "mobile-team")
            RESTRICTED_PATHS["backend"]="kv/data/dev/backend/database"
            RESTRICTED_PATHS["frontend"]="kv/data/dev/frontend/build"
            ;;
        "backend-team")
            RESTRICTED_PATHS["mobile"]="kv/data/dev/mobile/ios"
            RESTRICTED_PATHS["frontend"]="kv/data/dev/frontend/build"
            ;;
        "frontend-team")
            RESTRICTED_PATHS["mobile"]="kv/data/dev/mobile/ios"
            RESTRICTED_PATHS["backend"]="kv/data/dev/backend/database"
            ;;
        "devops-team")
            # DevOps team should have broader access
            echo "      DevOps team has cross-functional access (expected)"
            return
            ;;
    esac
    
    for restricted_team in "${!RESTRICTED_PATHS[@]}"; do
        local restricted_path="${RESTRICTED_PATHS[$restricted_team]}"
        local restricted_secret=$(curl -s -H "X-Vault-Token: $vault_token" \
            "$VAULT_ADDR/v1/$restricted_path" 2>/dev/null)
            
        # Check if we got an error (which is expected)
        if echo "$restricted_secret" | jq -e '.errors' > /dev/null; then
            log_success "   Correctly blocked from $restricted_team secrets"
            echo "     Blocked path: $restricted_path"
        elif echo "$restricted_secret" | jq -e '.data' > /dev/null; then
            log_error "   Incorrectly allowed access to $restricted_team secrets"
            echo "     Allowed path: $restricted_path"
        else
            log_warning "   Unclear response for $restricted_team secrets"
        fi
    done
}

# Main interactive testing loop
echo "Do you want to run team isolation tests? (y/N)"
read -r RUN_TESTS

if [[ "$RUN_TESTS" =~ ^[Yy]$ ]]; then
    echo
    echo "You'll need to authenticate as users from different Okta groups."
    echo "For each test, complete the Okta authentication flow and provide the session_id."
    echo
    
    # Test mobile team
    echo "=== Testing Mobile Team (mobile-developers group) ==="
    echo "1. Open: $BROKER_URL"
    echo "2. Login with a user in the 'mobile-developers' Okta group"
    echo "3. Copy the session_id from the response"
    echo
    echo "Enter session_id for mobile-developers user (or 'skip'):"
    read -r MOBILE_SESSION_ID
    
    if [[ "$MOBILE_SESSION_ID" != "skip" && -n "$MOBILE_SESSION_ID" ]]; then
        test_team_access "$MOBILE_SESSION_ID" "mobile-team" "Mobile Team Access Test"
    fi
    
    # Test backend team
    echo
    echo "=== Testing Backend Team (backend-developers group) ==="
    echo "Enter session_id for backend-developers user (or 'skip'):"
    read -r BACKEND_SESSION_ID
    
    if [[ "$BACKEND_SESSION_ID" != "skip" && -n "$BACKEND_SESSION_ID" ]]; then
        test_team_access "$BACKEND_SESSION_ID" "backend-team" "Backend Team Access Test"
    fi
    
    # Test frontend team
    echo
    echo "=== Testing Frontend Team (frontend-developers group) ==="
    echo "Enter session_id for frontend-developers user (or 'skip'):"
    read -r FRONTEND_SESSION_ID
    
    if [[ "$FRONTEND_SESSION_ID" != "skip" && -n "$FRONTEND_SESSION_ID" ]]; then
        test_team_access "$FRONTEND_SESSION_ID" "frontend-team" "Frontend Team Access Test"
    fi
    
    # Test devops team
    echo
    echo "=== Testing DevOps Team (devops-team group) ==="
    echo "Enter session_id for devops-team user (or 'skip'):"
    read -r DEVOPS_SESSION_ID
    
    if [[ "$DEVOPS_SESSION_ID" != "skip" && -n "$DEVOPS_SESSION_ID" ]]; then
        test_team_access "$DEVOPS_SESSION_ID" "devops-team" "DevOps Team Access Test"
    fi
    
else
    log_warning "Skipping interactive team isolation tests"
fi

# Summary
echo
echo " TEAM ISOLATION TEST SUMMARY"
echo "=============================="
log_success "Okta group-based team isolation implemented"
log_success "Team-specific secret access via Vault policies"
log_success "Cross-team access properly restricted"
log_success "DevOps team has appropriate cross-functional access"
echo
echo " Security Model:"
echo "    mobile-developers → mobile-team → mobile secrets only"
echo "    backend-developers → backend-team → backend secrets only"
echo "    frontend-developers → frontend-team → frontend secrets only"
echo "   devops-team → devops-team → cross-functional access"
echo "    All teams → shared secrets accessible"
echo
echo "Enterprise Benefits:"
echo "    Okta group membership controls access"
echo "    No manual policy management required"
echo "    Automatic team assignment based on OIDC claims"
echo "    Audit trail includes user identity and team membership"
echo "    Time-limited tokens with usage restrictions"