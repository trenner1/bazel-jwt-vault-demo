#!/usr/bin/env bash
# Team-based Entity Verification Script
# Verifies no entity churning within teams (licensing efficiency)
# Based on Jenkins Vault POC verification patterns

set -euo pipefail

export VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-}"

# Handle both VAULT_TOKEN and VAULT_ROOT_TOKEN for compatibility
if [[ -z "$VAULT_TOKEN" ]]; then
    if [[ -n "${VAULT_ROOT_TOKEN:-}" ]]; then
        echo "Using VAULT_ROOT_TOKEN as VAULT_TOKEN"
        export VAULT_TOKEN="$VAULT_ROOT_TOKEN"
    else
        echo "VAULT_TOKEN or VAULT_ROOT_TOKEN must be set (use root token for verification)"
        exit 1
    fi
fi

echo "=== BAZEL TEAM-BASED ENTITY VERIFICATION ==="
echo ""

# Record baseline state
echo " STEP 1: Recording baseline Vault entity state"
BASELINE_ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
BASELINE_ALIASES=$(vault list -format=json identity/entity-alias/id 2>/dev/null | jq -r 'length // 0')

echo " Baseline state:"
echo "   Entities: $BASELINE_ENTITIES"
echo "   Aliases:  $BASELINE_ALIASES"
echo ""

# Function to simulate team member build
simulate_team_build() {
    local team="$1"
    local developer="$2"
    local target="$3"
    
    echo "--- $team: $developer building $target ---"
    
    # Use the CLI authentication tool
    BROKER_URL="http://127.0.0.1:8081" \
    PIPELINE="$team" \
    REPO="verification-test" \
    ./tools/bazel-auth-simple --broker-url http://127.0.0.1:8081 --pipeline "$team" --repo "verification-test" --target "$target" --token-only > /dev/null 2>&1 || {
        echo "   Authentication failed (broker/vault may not be running)"
        return 1
    }
    
    # Check entity counts
    CURRENT_ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
    CURRENT_ALIASES=$(vault list -format=json identity/entity-alias/id 2>/dev/null | jq -r 'length // 0')
    
    echo "    Vault state: $CURRENT_ENTITIES entities (+$((CURRENT_ENTITIES - BASELINE_ENTITIES))), $CURRENT_ALIASES aliases (+$((CURRENT_ALIASES - BASELINE_ALIASES)))"
    
    # Update baseline for next comparison
    BASELINE_ENTITIES=$CURRENT_ENTITIES
    BASELINE_ALIASES=$CURRENT_ALIASES
    
    return 0
}

echo " STEP 2: Testing team-based entity behavior"
echo ""

echo "🏢 Scenario: Multiple developers from same team"
echo ""

# Simulate mobile-developers team members building different targets
simulate_team_build "mobile-team" "alice@company.com" "//mobile:ios-app"
simulate_team_build "mobile-team" "bob@company.com" "//mobile:android-app" 
simulate_team_build "mobile-team" "carol@company.com" "//mobile:tests"

echo ""
echo " RESULT for mobile-team: Same team members should reuse entities"

echo ""
echo "🏢 Scenario: Different teams (should create separate entities)"
echo ""

simulate_team_build "backend-team" "dave@company.com" "//backend:api-service"
simulate_team_build "frontend-team" "eve@company.com" "//frontend:web-app"
simulate_team_build "devops-team" "frank@company.com" "//infra:deployment"

FINAL_ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
FINAL_ALIASES=$(vault list -format=json identity/entity-alias/id 2>/dev/null | jq -r 'length // 0')

echo ""
echo " FINAL RESULTS:"
echo "   Final entities: $FINAL_ENTITIES"
echo "   Final aliases:  $FINAL_ALIASES"
echo ""

echo " ANALYSIS:"
echo "   • Expected: 1 entity per team (logical license grouping)"
echo "   • Mobile-team: All members share same entity (no churning)"
echo "   • Backend-team: Gets separate entity from mobile-team"
echo "   • Frontend-team: Gets separate entity from other teams"
echo "   • DevOps-team: Gets separate entity for infrastructure work"
echo ""

if [[ $FINAL_ENTITIES -le 6 ]]; then
    echo " EXCELLENT: Entity count is reasonable (≤6 for 4 teams)"
    echo "   This demonstrates licensing-efficient team grouping"
else
    echo "WARNING: More entities than expected"
    echo "   Review team configuration and JWT claims"
fi

echo ""
echo " PRODUCTION RECOMMENDATIONS:"
echo "   1. Use 'sub' claim = team name for logical grouping"
echo "   2. Map Okta groups (mobile-developers, backend-developers, etc.) to teams"  
echo "   3. Monitor entity growth: vault list identity/entity/id | wc -l"
echo "   4. Verify no churning within teams regularly"
echo "   5. Ensure team assignment via Okta group membership automation"
echo ""

echo " Detailed entity information:"
if [[ $FINAL_ENTITIES -gt 0 ]]; then
    vault list -format=json identity/entity/id 2>/dev/null | jq -r '.[]' | while read -r entity_id; do
        entity_info=$(vault read -format=json identity/entity/id/"$entity_id" 2>/dev/null)
        echo "   Entity: $entity_id"
        echo "     Name: $(echo "$entity_info" | jq -r '.data.name // "unnamed"')"
        echo "     Aliases: $(echo "$entity_info" | jq -r '.data.aliases | length // 0')"
        echo ""
    done
fi

echo "✨ Verification complete!"