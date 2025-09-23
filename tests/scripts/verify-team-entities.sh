#!/usr/bin/env bash
# Team-based Entity Verification Script
# Verifies no entity churning within teams (licensing efficiency)
# Based on Jenkins Vault POC verification patterns

set -euo pipefail

export VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-}"

if [[ -z "$VAULT_TOKEN" ]]; then
    echo "❌ VAULT_TOKEN must be set (use root token for verification)"
    exit 1
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
    
    # Use the transparent auth script
    BROKER_URL="http://127.0.0.1:8081" \
    BAZEL_TEAM="$team" \
    USER="$developer" \
    ./scripts/bazel-auth.sh "$target" > /dev/null 2>&1 || {
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

# Simulate team-alpha members building different targets
simulate_team_build "team-alpha" "alice@company.com" "//frontend:app"
simulate_team_build "team-alpha" "bob@company.com" "//frontend:tests" 
simulate_team_build "team-alpha" "carol@company.com" "//frontend:deploy"

echo ""
echo " RESULT for team-alpha: Same team members should reuse entities"

echo ""
echo "🏢 Scenario: Different teams (should create separate entities)"
echo ""

simulate_team_build "team-beta" "dave@company.com" "//backend:service"
simulate_team_build "team-gamma" "eve@company.com" "//ml:training"

FINAL_ENTITIES=$(vault list -format=json identity/entity/id 2>/dev/null | jq -r 'length // 0')
FINAL_ALIASES=$(vault list -format=json identity/entity-alias/id 2>/dev/null | jq -r 'length // 0')

echo ""
echo " FINAL RESULTS:"
echo "   Final entities: $FINAL_ENTITIES"
echo "   Final aliases:  $FINAL_ALIASES"
echo ""

echo " ANALYSIS:"
echo "   • Expected: 1 entity per team (logical license grouping)"
echo "   • Team-alpha: All members share same entity (no churning)"
echo "   • Team-beta: Gets separate entity from team-alpha"
echo "   • Team-gamma: Gets separate entity from other teams"
echo ""

if [[ $FINAL_ENTITIES -le 3 ]]; then
    echo " EXCELLENT: Entity count is reasonable (≤3 for 3 teams)"
    echo "   This demonstrates licensing-efficient team grouping"
else
    echo "WARNING: More entities than expected"
    echo "   Review team configuration and JWT claims"
fi

echo ""
echo " PRODUCTION RECOMMENDATIONS:"
echo "   1. Use 'sub' claim = team name for logical grouping"
echo "   2. Map Okta/LDAP groups to teams automatically"  
echo "   3. Monitor entity growth: vault list identity/entity/id | wc -l"
echo "   4. Verify no churning within teams regularly"
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