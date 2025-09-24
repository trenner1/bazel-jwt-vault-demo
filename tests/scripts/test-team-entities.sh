#!/bin/bash
set -euo pipefail

# Interactive Test script to prove team-based entity creation
# This script demonstrates that users from the same team share entities
# REQUIRES: Real Okta users to authenticate through the browser

export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=${VAULT_TOKEN:-}

# Handle both VAULT_TOKEN and VAULT_ROOT_TOKEN for compatibility
if [[ -z "$VAULT_TOKEN" ]]; then
    if [[ -n "${VAULT_ROOT_TOKEN:-}" ]]; then
        echo "Using VAULT_ROOT_TOKEN as VAULT_TOKEN"
        export VAULT_TOKEN="$VAULT_ROOT_TOKEN"
    else
        echo "VAULT_TOKEN or VAULT_ROOT_TOKEN must be set"
        exit 1
    fi
fi

echo " INTERACTIVE TEAM-BASED ENTITY TESTING"
echo "======================================="
echo
echo "This test requires REAL users from your Okta account to authenticate."
echo "You'll need users assigned to these Okta groups:"
echo "  - mobile-developers"
echo "  - backend-developers"
echo "  - frontend-developers"
echo "  - devops-team"
echo

echo " Initial state:"
INITIAL_ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
echo "   Entities: $INITIAL_ENTITIES"
echo

# Function for interactive user authentication
interactive_auth_test() {
    local team="$1"
    local team_name="$2"
    local user_prompt="$3"
    
    echo "=== $team_name Team Authentication ==="
    echo
    echo "$user_prompt"
    echo
    echo "Steps:"
    echo "1. Open browser to: http://localhost:8081/auth/url"
    echo "2. Complete Okta authentication"
    echo "3. Check that you're in the '$team_name' group in Okta"
    echo "4. Return here after authentication"
    echo
    
    read -p "Press Enter when ready to check authentication results..."
    
    # Check if there are any active sessions for this team
    echo "Checking current Vault entities..."
    
    CURRENT_ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
    
    echo "   Current entities: $CURRENT_ENTITIES"
    echo "   Change from initial: +$((CURRENT_ENTITIES - INITIAL_ENTITIES))"
    
    return $CURRENT_ENTITIES
}

# Store entity counts for analysis
declare -a entity_counts=()

echo "SCENARIO 1: Multiple users from mobile-developers group"
echo "-------------------------------------------------------"
echo

interactive_auth_test "mobile-team" "Mobile" "Have a user from the 'mobile-developers' Okta group authenticate:"
entity_counts+=($(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0'))

echo
read -p "Have ANOTHER user from 'mobile-developers' authenticate, then press Enter..."
MOBILE_2_ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
entity_counts+=($MOBILE_2_ENTITIES)
echo "   Entities after 2nd mobile user: $MOBILE_2_ENTITIES"

echo
echo " MOBILE TEAM ANALYSIS:"
if [[ ${entity_counts[1]} -eq ${entity_counts[0]} ]]; then
    echo "    ✅ SUCCESS: Second mobile user REUSED existing entity!"
    echo "    This demonstrates licensing efficiency within teams."
else
    echo "    ❌ ISSUE: Second mobile user created a new entity"
    echo "    Check team assignment and entity configuration."
fi
echo

echo "SCENARIO 2: User from different team (backend-developers)"
echo "--------------------------------------------------------"
echo

read -p "Have a user from 'backend-developers' authenticate, then press Enter..."
BACKEND_ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
entity_counts+=($BACKEND_ENTITIES)

echo "   Entities after backend user: $BACKEND_ENTITIES"
echo

echo " CROSS-TEAM ANALYSIS:"
if [[ $BACKEND_ENTITIES -gt ${entity_counts[1]} ]]; then
    echo "    ✅ SUCCESS: Backend team created separate entity from mobile!"
    echo "    This demonstrates proper team isolation."
else
    echo "    ❌ ISSUE: Backend user didn't create separate entity"
    echo "    Check team isolation configuration."
fi
echo

echo " FINAL RESULTS:"
FINAL_ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
echo "   Initial entities: $INITIAL_ENTITIES"
echo "   Final entities: $FINAL_ENTITIES"
echo "   Entities created: $((FINAL_ENTITIES - INITIAL_ENTITIES))"
echo

echo " IDEAL BEHAVIOR:"
echo "   • Users within same team → Share entity (licensing efficiency)"
echo "   • Users from different teams → Separate entities (team isolation)"
echo "   • Expected entities created: ≤ number of teams tested"
echo

if [[ $((FINAL_ENTITIES - INITIAL_ENTITIES)) -le 2 ]]; then
    echo " ✅ EXCELLENT: Entity growth is efficient!"
    echo "   Created ≤2 entities for 2 teams tested"
else
    echo " ⚠️  REVIEW NEEDED: More entities created than expected"
    echo "   Consider reviewing team assignment logic"
fi

echo
echo " To test more teams, run additional authentication tests with:"
echo "   - frontend-developers group users"
echo "   - devops-team group users"
echo
echo " View detailed entity information:"
echo "   vault list identity/entity/id"
echo "   vault read identity/entity/id/<entity-id>"

echo
echo "✨ Interactive team entity test complete!"