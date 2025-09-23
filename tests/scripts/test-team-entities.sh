#!/bin/bash
set -euo pipefail

# Test script to prove team-based entity creation
# This script demonstrates that users from the same team share entities

export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=${VAULT_TOKEN:-"your-vault-root-token-here"}

echo " TESTING TEAM-BASED ENTITY CREATION"
echo "====================================="
echo

echo " Initial state:"
INITIAL_ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
echo "   Entities: $INITIAL_ENTITIES"
echo

# Create a simple JWT token for testing
# In reality this would come from Okta, but we'll create a minimal one for testing
create_test_jwt() {
    local groups="$1"
    local email="$2"
    
    # Simple JWT payload (this is just for testing - in production this comes from Okta)
    local header='{"alg":"none","typ":"JWT"}'
    local payload=$(echo "{\"email\":\"$email\",\"groups\":[$groups],\"aud\":\"0oavom81m9J0lBtxq697\",\"exp\":$(($(date +%s) + 3600))}" | base64 -w 0 | tr -d '=')
    local signature=""
    
    echo "$header.$payload.$signature"
}

# Test function to authenticate with Vault using JWT
test_jwt_auth() {
    local groups="$1"
    local email="$2"
    local role="$3"
    local description="$4"
    
    echo " Testing: $description"
    echo "   Email: $email"
    echo "   Groups: $groups"
    echo "   Role: $role"
    
    # Create test JWT (normally this would come from Okta)
    local jwt_token=$(create_test_jwt "$groups" "$email")
    
    # Attempt to authenticate with Vault
    local auth_response=$(curl -s -X POST "$VAULT_ADDR/v1/auth/jwt/login" \
        -d "{\"jwt\":\"$jwt_token\",\"role\":\"$role\"}" 2>/dev/null || echo '{"errors":["auth_failed"]}')
    
    if echo "$auth_response" | jq -e '.auth.client_token' > /dev/null 2>&1; then
        local vault_token=$(echo "$auth_response" | jq -r '.auth.client_token')
        local entity_id=$(echo "$auth_response" | jq -r '.auth.entity_id // "none"')
        
        echo "    Authentication successful"
        echo "    Entity ID: $entity_id"
        echo "   🎫 Token: ${vault_token:0:20}..."
        echo "   $entity_id"  # Return entity ID for comparison
    else
        echo "   ❌ Authentication failed"
        echo "   Error: $(echo "$auth_response" | jq -r '.errors[0] // "unknown"')"
        echo "   none"
    fi
    echo
}

echo "🏢 SCENARIO 1: Multiple users from mobile-developers team"
echo "----------------------------------------------------"

# Test users from same team
entity1=$(test_jwt_auth '"mobile-developers"' "alice@company.com" "mobile-team" "Alice from mobile team")
entity2=$(test_jwt_auth '"mobile-developers"' "bob@company.com" "mobile-team" "Bob from mobile team") 
entity3=$(test_jwt_auth '"mobile-developers"' "carol@company.com" "mobile-team" "Carol from mobile team")

echo " ANALYSIS:"
if [[ "$entity1" != "none" && "$entity1" == "$entity2" && "$entity2" == "$entity3" ]]; then
    echo "    SUCCESS: All mobile team members share the same entity!"
    echo "    Shared Entity ID: $entity1"
else
    echo "   ❌ FAILURE: Team members have different entities"
    echo "    Entity IDs: $entity1, $entity2, $entity3"
fi
echo

echo "🏢 SCENARIO 2: User from different team"
echo "--------------------------------------"

entity4=$(test_jwt_auth '"backend-developers"' "dave@company.com" "backend-team" "Dave from backend team")

echo " ANALYSIS:"
if [[ "$entity4" != "none" && "$entity4" != "$entity1" ]]; then
    echo "    SUCCESS: Backend team has separate entity from mobile team!"
    echo "    Mobile Entity: $entity1"
    echo "    Backend Entity: $entity4"
else
    echo "   ❌ FAILURE: Backend team entity issue"
    echo "    Backend Entity: $entity4"
fi
echo

echo " Final state:"
FINAL_ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
echo "   Entities: $FINAL_ENTITIES"
echo

if [[ $FINAL_ENTITIES -eq 2 ]]; then
    echo " PERFECT: 2 entities created (1 per team) instead of 4 (1 per user)"
    echo "   💰 Licensing efficiency achieved!"
else
    echo "Expected 2 entities (1 per team), got $FINAL_ENTITIES"
fi

echo
echo "✨ Team-based entity test complete!"