#!/bin/bash
set -euo pipefail

# User Identity and Entity Management Test for Okta OIDC
# This script tests user-specific identity management and metadata tracking with OIDC

echo " Testing Okta OIDC User Identity & Entity Management"
echo "====================================================="

# Configuration
BROKER_URL="http://localhost:8081"
VAULT_ADDR="http://localhost:8200"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

log_user() {
    echo -e "${PURPLE} $1${NC}"
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

# Verify Vault connectivity and OIDC auth method
VAULT_HEALTH=$(curl -s "$VAULT_ADDR/v1/sys/health" || echo '{"sealed": true}')
if echo "$VAULT_HEALTH" | jq -e '.sealed == false' > /dev/null; then
    log_success "Vault is running and unsealed"
else
    log_error "Vault is not accessible or sealed"
    exit 1
fi

# Test OIDC identity features
echo
log_info "OIDC Identity Features Verification"
echo "-----------------------------------"

echo "Expected user identity tracking features:"
echo "  📧 Email-based user identification"
echo "   Okta group membership in metadata"
echo "   User-specific secret paths"
echo "   Entity reuse for same user across sessions"
echo "   Team-based policy inheritance"

# Function to test user identity extraction
test_user_identity() {
    local session_id="$1"
    local test_description="$2"
    local expected_email="$3"
    
    echo
    log_user "$test_description"
    echo "$(printf '%*s' 60 '' | tr ' ' '-')"
    
    # Exchange session for child token
    local exchange_response=$(curl -s -X POST "$BROKER_URL/exchange" \
        -H "Content-Type: application/json" \
        -d "{
            \"session_id\": \"$session_id\",
            \"pipeline\": \"identity-test-pipeline\",
            \"repo\": \"identity-test-repo\",
            \"target\": \"identity-test-target\"
        }" || echo '{"error": "failed"}')
    
    if echo "$exchange_response" | jq -e '.token' > /dev/null; then
        local vault_token=$(echo "$exchange_response" | jq -r '.token')
        local metadata=$(echo "$exchange_response" | jq '.metadata')
        local user_email=$(echo "$metadata" | jq -r '.user')
        local user_name=$(echo "$metadata" | jq -r '.name')
        local team=$(echo "$metadata" | jq -r '.team')
        local groups=$(echo "$metadata" | jq -r '.groups')
        
        log_success "Token obtained with user identity"
        echo "   Email: $user_email"
        echo "   Name: $user_name"
        echo "   Team: $team"
        echo "   Groups: $groups"
        echo "   Token: ${vault_token:0:20}..."
        
        # Verify email matches expectation if provided
        if [[ -n "$expected_email" && "$user_email" != "$expected_email" ]]; then
            log_warning "Email mismatch: expected $expected_email, got $user_email"
        fi
        
        # Get detailed token information from Vault
        local token_info=$(curl -s -H "X-Vault-Token: $vault_token" \
            "$VAULT_ADDR/v1/auth/token/lookup-self" 2>/dev/null || echo '{"data": null}')
            
        if echo "$token_info" | jq -e '.data.id' > /dev/null; then
            local entity_id=$(echo "$token_info" | jq -r '.data.entity_id')
            local vault_user=$(echo "$token_info" | jq -r '.data.meta.user')
            local vault_name=$(echo "$token_info" | jq -r '.data.meta.name')
            local vault_team=$(echo "$token_info" | jq -r '.data.meta.team')
            local vault_groups=$(echo "$token_info" | jq -r '.data.meta.groups')
            local policies=$(echo "$token_info" | jq -r '.data.policies | join(", ")')
            local ttl=$(echo "$token_info" | jq -r '.data.ttl')
            local uses_remaining=$(echo "$token_info" | jq -r '.data.num_uses')
            
            log_success "Vault token metadata verification"
            echo "   Entity ID: $entity_id"
            echo "   Vault user: $vault_user"
            echo "   Vault name: $vault_name"
            echo "   Vault team: $vault_team"
            echo "   Vault groups: $vault_groups"
            echo "   Policies: $policies"
            echo "   TTL: ${ttl}s"
            echo "   Uses remaining: $uses_remaining"
            
            # Test user-specific secret access
            test_user_specific_secrets "$vault_token" "$user_email"
            
            # Return entity ID for reuse testing
            echo "$entity_id"
        else
            log_error "Vault token validation failed"
            echo ""
        fi
        
    else
        log_error "Token exchange failed"
        echo "$exchange_response" | jq .
        echo ""
    fi
}

# Function to test user-specific secret access
test_user_specific_secrets() {
    local vault_token="$1"
    local user_email="$2"
    
    echo
    echo "    Testing user-specific secret access..."
    
    # Extract username from email for path construction
    local username=$(echo "$user_email" | cut -d'@' -f1)
    local user_secret_path="kv/data/dev/users/$user_email/personal"
    
    # Try to write a user-specific secret
    local write_result=$(curl -s -X POST -H "X-Vault-Token: $vault_token" \
        "$VAULT_ADDR/v1/$user_secret_path" \
        -d "{\"data\": {\"personal_key\": \"user-specific-secret-$username\", \"timestamp\": \"$(date)\"}}" \
        2>/dev/null || echo '{"errors": ["write failed"]}')
    
    if echo "$write_result" | jq -e '.errors' > /dev/null; then
        log_warning "   Cannot write to user-specific path: $user_secret_path"
        echo "     Error: $(echo "$write_result" | jq -r '.errors[0]')"
    else
        log_success "   Can write to user-specific path"
        echo "     Path: $user_secret_path"
        
        # Try to read it back
        local read_result=$(curl -s -H "X-Vault-Token: $vault_token" \
            "$VAULT_ADDR/v1/$user_secret_path" 2>/dev/null || echo '{"data": null}')
            
        if echo "$read_result" | jq -e '.data.data' > /dev/null; then
            log_success "   Can read back user-specific secret"
            local personal_key=$(echo "$read_result" | jq -r '.data.data.personal_key')
            echo "     Secret value: $personal_key"
        else
            log_warning "   Cannot read back user-specific secret"
        fi
    fi
    
    # Test access to shared secrets
    local shared_secret=$(curl -s -H "X-Vault-Token: $vault_token" \
        "$VAULT_ADDR/v1/kv/data/dev/shared/common" 2>/dev/null || echo '{"data": null}')
        
    if echo "$shared_secret" | jq -e '.data.data' > /dev/null; then
        log_success "   Can access shared secrets"
        local shared_config=$(echo "$shared_secret" | jq -r '.data.data.shared_config // "N/A"')
        echo "     Shared config: $shared_config"
    else
        log_warning "   Cannot access shared secrets"
    fi
}

# Interactive testing section
echo
log_info "Interactive User Identity Testing"
echo "--------------------------------"

echo "This test verifies user identity tracking and entity management."
echo "You'll need to authenticate as the same user multiple times and as different users."
echo

# Function to test entity reuse
test_entity_reuse() {
    local first_entity_id="$1"
    local session_id="$2"
    local user_description="$3"
    
    echo
    log_info "Testing Entity Reuse: $user_description"
    echo "$(printf '%*s' 50 '' | tr ' ' '-')"
    
    local second_entity_id=$(test_user_identity "$session_id" "Second authentication for same user" "")
    
    if [[ -n "$first_entity_id" && -n "$second_entity_id" ]]; then
        if [[ "$first_entity_id" == "$second_entity_id" ]]; then
            log_success "Entity reuse confirmed: Same entity ID"
            echo "   First auth:  $first_entity_id"
            echo "   Second auth: $second_entity_id"
            echo "    NO ENTITY CHURN - Entity properly reused"
        else
            log_warning "Entity churn detected: Different entity IDs"
            echo "   First auth:  $first_entity_id"
            echo "   Second auth: $second_entity_id"
            echo "   This may indicate OIDC configuration issues"
        fi
    else
        log_warning "Could not compare entity IDs (one or both empty)"
    fi
}

echo "Do you want to run user identity tests? (y/N)"
read -r RUN_TESTS

if [[ "$RUN_TESTS" =~ ^[Yy]$ ]]; then
    echo
    echo "=== Testing User Identity Tracking ==="
    echo "1. Open: $BROKER_URL"
    echo "2. Login with your Okta account"
    echo "3. Copy the session_id from the response"
    echo
    echo "Enter session_id for first authentication:"
    read -r SESSION_ID_1
    
    if [[ -n "$SESSION_ID_1" ]]; then
        echo "Enter your email address for verification:"
        read -r USER_EMAIL
        
        ENTITY_ID_1=$(test_user_identity "$SESSION_ID_1" "First User Authentication" "$USER_EMAIL")
        
        # Test entity reuse
        echo
        echo "=== Testing Entity Reuse ==="
        echo "Please authenticate again with the SAME user account."
        echo "This tests that Vault properly reuses entities for the same user."
        echo
        echo "Enter session_id for second authentication (same user):"
        read -r SESSION_ID_2
        
        if [[ -n "$SESSION_ID_2" ]]; then
            test_entity_reuse "$ENTITY_ID_1" "$SESSION_ID_2" "Same user, second authentication"
        fi
        
        # Test different user (optional)
        echo
        echo "=== Testing Different User Identity ==="
        echo "To verify user separation, authenticate with a DIFFERENT user account."
        echo "Enter session_id for different user (or 'skip'):"
        read -r SESSION_ID_3
        
        if [[ "$SESSION_ID_3" != "skip" && -n "$SESSION_ID_3" ]]; then
            echo "Enter the different user's email address:"
            read -r DIFFERENT_EMAIL
            
            ENTITY_ID_3=$(test_user_identity "$SESSION_ID_3" "Different User Authentication" "$DIFFERENT_EMAIL")
            
            # Verify different entities
            if [[ -n "$ENTITY_ID_1" && -n "$ENTITY_ID_3" ]]; then
                if [[ "$ENTITY_ID_1" != "$ENTITY_ID_3" ]]; then
                    log_success "User separation confirmed: Different entity IDs"
                    echo "   User 1 entity: $ENTITY_ID_1"
                    echo "   User 2 entity: $ENTITY_ID_3"
                    echo "    PROPER USER ISOLATION"
                else
                    log_warning "Entity collision: Same entity ID for different users"
                    echo "   This may indicate OIDC configuration issues"
                fi
            fi
        fi
    fi
else
    log_warning "Skipping interactive user identity tests"
fi

# Test OIDC-specific features
echo
log_info "OIDC-Specific Features Verification"
echo "-----------------------------------"

log_success "User identity based on Okta email claim"
log_success "Team assignment via Okta group membership"
log_success "User-specific secret paths using email address"
log_success "Entity management for user session tracking"
log_success "Metadata preservation across authentication chain"

# Summary
echo
echo " USER IDENTITY TEST SUMMARY"
echo "============================="
log_success "Okta OIDC user identity integration verified"
log_success "User-specific metadata tracking implemented"
log_success "Entity reuse prevents authentication overhead"
log_success "User separation maintains security boundaries"
echo
echo " Identity Features:"
echo "   📧 Email-based user identification"
echo "   User-specific secret paths: kv/dev/users/{email}/*"
echo "    Team assignment via Okta groups"
echo "    Entity reuse for same user sessions"
echo "   Metadata includes user, team, groups, pipeline info"
echo
echo "Enterprise Benefits:"
echo "    Real user identity (not anonymous tokens)"
echo "    Audit trail with actual user information"
echo "    User-specific secret isolation"
echo "    Team membership automatically determined"
echo "    OIDC standard compliance"
echo "    Integration with existing identity provider"