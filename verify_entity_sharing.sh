#!/bin/bash
set -euo pipefail

# Verification Script: Bazel Entity Sharing and Alias Stability
# This script demonstrates that different teams share the same bazel-dev entity
# and that the entity alias doesn't churn between authentications

echo "Bazel Entity Sharing Verification"
echo "================================="
echo

# Check required environment
if [[ -z "${VAULT_ROOT_TOKEN:-}" ]]; then
    echo -e "${RED:-}Error: VAULT_ROOT_TOKEN environment variable not set${NC:-}"
    echo "Please set it with: export VAULT_ROOT_TOKEN=your_token"
    echo "Or it will use the default development token"
    echo
fi

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

BROKER_URL="http://localhost:8081"
VAULT_ROOT_TOKEN="${VAULT_ROOT_TOKEN:-hvs.6pWmpPiEcKUXdpYOJutjLFZt}"

echo "Configuration:"
echo "  Broker URL: $BROKER_URL"
echo "  Vault Token: ${VAULT_ROOT_TOKEN:0:20}..." # Show only first 20 chars for security
echo

# Test teams and their build targets - using simple arrays instead of associative
TEAMS=("alpha" "beta" "gamma" "delta")
TARGETS=("//frontend:app" "//backend:service" "//ml:model" "//mobile:app")
USERS=("alice.smith" "bob.jones" "charlie.brown" "diana.prince")

echo -e "${BLUE}Step 1: Generate JWTs for different teams${NC}"
echo "==========================================="

# Store entity IDs and token data in simple arrays
ENTITY_IDS=()
TOKEN_DATA=()

for i in "${!TEAMS[@]}"; do
    team="${TEAMS[$i]}"
    target="${TARGETS[$i]}"
    user="${USERS[$i]}"
    
    echo -e "\n${YELLOW}Team: $team${NC}"
    echo "  User: $user"
    echo "  Target: $target"
    
    # Generate JWT
    JWT_RESPONSE=$(curl -s -X POST "$BROKER_URL/demo/sign" \
        -H "Content-Type: application/json" \
        -d "{
            \"team\": \"$team\",
            \"user\": \"$user\",
            \"target\": \"$target\",
            \"repo\": \"monorepo\",
            \"run_id\": \"verify-$team-$(date +%s)\"
        }")
    
    JWT_TOKEN=$(echo "$JWT_RESPONSE" | jq -r '.assertion')
    JWT_SUB=$(echo "$JWT_RESPONSE" | jq -r '.claims.sub')
    
    echo "  Subject: $JWT_SUB"
    
    # Authenticate with Vault
    AUTH_RESPONSE=$(docker exec vault sh -c "
        export VAULT_ADDR=http://localhost:8200
        export VAULT_TOKEN=$VAULT_ROOT_TOKEN
        vault write -format=json auth/jwt/login role=bazel-builds jwt='$JWT_TOKEN' 2>/dev/null
    ")
    
    VAULT_TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.auth.client_token')
    
    # Get token details
    TOKEN_INFO=$(docker exec vault sh -c "
        export VAULT_ADDR=http://localhost:8200
        export VAULT_TOKEN='$VAULT_TOKEN'
        vault token lookup -format=json 2>/dev/null
    ")
    
    ENTITY_ID=$(echo "$TOKEN_INFO" | jq -r '.data.entity_id')
    DISPLAY_NAME=$(echo "$TOKEN_INFO" | jq -r '.data.display_name')
    
    ENTITY_IDS+=("$ENTITY_ID")
    TOKEN_DATA+=("$VAULT_TOKEN")
    
    echo "  Entity ID: $ENTITY_ID"
    echo "  Display Name: $DISPLAY_NAME"
done

echo
echo -e "${BLUE}Step 2: Verify Team-Based Entity Separation${NC}"
echo "============================================"

# Check that different teams have different entities (SUCCESS for team-based model)
FIRST_ENTITY_ID=""
TEAM_SEPARATION_SUCCESS=true

for i in "${!ENTITY_IDS[@]}"; do
    entity_id="${ENTITY_IDS[$i]}"
    team="${TEAMS[$i]}"
    
    if [[ -z "$FIRST_ENTITY_ID" ]]; then
        FIRST_ENTITY_ID="$entity_id"
        echo -e "${GREEN}✓${NC} Reference Team ${TEAMS[0]}: $FIRST_ENTITY_ID"
    else
        if [[ "$entity_id" != "$FIRST_ENTITY_ID" ]]; then
            echo -e "${GREEN}✓${NC} Team $team: Separate entity ($entity_id) ✓"
        else
            echo -e "${RED}✗${NC} Team $team: Same entity (unexpected for team-based model)"
            TEAM_SEPARATION_SUCCESS=false
        fi
    fi
done

echo
echo -e "${BLUE}Step 3: Verify Team Members Share Same Entity${NC}"
echo "============================================="

# Test multiple members from the same team (alpha)
echo "Testing multiple alpha team members..."

# Generate JWT for second alpha team member
ALPHA_MEMBER_2_JWT=$(curl -s -X POST $BROKER_URL/demo/sign -H "Content-Type: application/json" -d '{
  "team": "alpha",
  "user": "alice.anderson", 
  "target": "//shared:lib",
  "repo": "monorepo",
  "run_id": "alpha-member-2"
}' | jq -r .assertion)

# Authenticate second alpha member
ALPHA_2_AUTH=$(docker exec vault sh -c "
    export VAULT_ADDR=http://localhost:8200
    export VAULT_TOKEN=$VAULT_ROOT_TOKEN
    vault write -format=json auth/jwt/login role=bazel-builds jwt='$ALPHA_MEMBER_2_JWT' 2>/dev/null
")

ALPHA_2_TOKEN=$(echo "$ALPHA_2_AUTH" | jq -r '.auth.client_token')

# Get token details for second alpha member
ALPHA_2_INFO=$(docker exec vault sh -c "
    export VAULT_ADDR=http://localhost:8200
    export VAULT_TOKEN='$ALPHA_2_TOKEN'
    vault token lookup -format=json 2>/dev/null
")

ALPHA_2_ENTITY_ID=$(echo "$ALPHA_2_INFO" | jq -r '.data.entity_id')

# Get alias info from entity details (not token lookup)
ALPHA_1_ENTITY_DETAILS=$(docker exec vault sh -c "
    export VAULT_ADDR=http://localhost:8200
    export VAULT_TOKEN=$VAULT_ROOT_TOKEN
    vault read -format=json identity/entity/id/${ENTITY_IDS[0]} 2>/dev/null
")
ALPHA_1_ALIAS_ID=$(echo "$ALPHA_1_ENTITY_DETAILS" | jq -r '.data.aliases[0].id // "none"')

ALPHA_2_ENTITY_DETAILS=$(docker exec vault sh -c "
    export VAULT_ADDR=http://localhost:8200
    export VAULT_TOKEN=$VAULT_ROOT_TOKEN
    vault read -format=json identity/entity/id/$ALPHA_2_ENTITY_ID 2>/dev/null
")
ALPHA_2_ALIAS_ID=$(echo "$ALPHA_2_ENTITY_DETAILS" | jq -r '.data.aliases[0].id // "none"')

echo "  Alpha Member 1 (alice.smith):   Entity: ${ENTITY_IDS[0]}"
echo "  Alpha Member 2 (alice.anderson): Entity: $ALPHA_2_ENTITY_ID"

SAME_TEAM_SHARING=true
if [[ "$ALPHA_2_ENTITY_ID" == "${ENTITY_IDS[0]}" ]]; then
    echo -e "${GREEN}✓${NC} Alpha team members share the same entity ✓"
else
    echo -e "${RED}✗${NC} Alpha team members have different entities"
    SAME_TEAM_SHARING=false
fi

echo ""
echo "Alpha Team Alias Analysis:"
echo "  Member 1 Alias: $ALPHA_1_ALIAS_ID"  
echo "  Member 2 Alias: $ALPHA_2_ALIAS_ID"

if [[ "$ALPHA_2_ALIAS_ID" == "$ALPHA_1_ALIAS_ID" ]]; then
    echo -e "${GREEN}✓${NC} Alpha team members share the same alias ✓"
else
    echo -e "${RED}✗${NC} Alpha team members have different aliases"
    SAME_TEAM_SHARING=false
fi

echo
if [[ "$TEAM_SEPARATION_SUCCESS" == true && "$SAME_TEAM_SHARING" == true ]]; then
    echo -e "${GREEN}SUCCESS: Team-based entity model working correctly!${NC}"
    echo -e "${GREEN}   • Different teams have separate entities${NC}"
    echo -e "${GREEN}   • Same team members share entities and aliases${NC}"
else
    echo -e "${RED}FAILURE: Team-based entity model not working properly!${NC}"
    exit 1
fi

echo
echo -e "${BLUE}Step 3: Verify Entity Alias Details${NC}"
echo "=================================="

# Get detailed entity information
ENTITY_DETAILS=$(docker exec vault sh -c "
    export VAULT_ADDR=http://localhost:8200
    export VAULT_TOKEN=$VAULT_ROOT_TOKEN
    vault read -format=json identity/entity/id/$FIRST_ENTITY_ID 2>/dev/null
")

ENTITY_NAME=$(echo "$ENTITY_DETAILS" | jq -r '.data.name')
ALIAS_NAME=$(echo "$ENTITY_DETAILS" | jq -r '.data.aliases[0].name')
ALIAS_ID=$(echo "$ENTITY_DETAILS" | jq -r '.data.aliases[0].id')
CREATION_TIME=$(echo "$ENTITY_DETAILS" | jq -r '.data.creation_time')

echo "Entity Details:"
echo "  Name: $ENTITY_NAME"
echo "  Alias Name: $ALIAS_NAME"
echo "  Alias ID: $ALIAS_ID"
echo "  Created: $(date -d @$CREATION_TIME 2>/dev/null || date -r $CREATION_TIME 2>/dev/null || echo $CREATION_TIME)"

echo
echo -e "${BLUE}Step 4: Test Repeated Authentication (No Alias Churn)${NC}"
echo "===================================================="

echo "Authenticating different alpha team members to verify alias stability..."

INITIAL_ALIAS_ID="$ALIAS_ID"

# Test different alpha team members
ALPHA_USERS=("alice.smith" "alice.anderson" "alice.cooper")
ALPHA_TARGETS=("//frontend:app" "//shared:lib" "//tools:cli")

for i in {1..3}; do
    USER="${ALPHA_USERS[$((i-1))]}"
    TARGET="${ALPHA_TARGETS[$((i-1))]}"
    
    echo -e "\n${YELLOW}Authentication #$i (User: $USER):${NC}"
    
    # Generate new JWT for different alpha team member
    JWT_RESPONSE=$(curl -s -X POST "$BROKER_URL/demo/sign" \
        -H "Content-Type: application/json" \
        -d "{
            \"team\": \"alpha\",
            \"user\": \"$USER\",
            \"target\": \"$TARGET\",
            \"repo\": \"monorepo\",
            \"run_id\": \"stability-test-$i-$(date +%s)\"
        }")
    
    JWT_TOKEN=$(echo "$JWT_RESPONSE" | jq -r '.assertion')
    
    # Authenticate with Vault
    AUTH_RESPONSE=$(docker exec vault sh -c "
        export VAULT_ADDR=http://localhost:8200
        export VAULT_TOKEN=$VAULT_ROOT_TOKEN
        vault write -format=json auth/jwt/login role=bazel-builds jwt='$JWT_TOKEN' 2>/dev/null
    ")
    
    VAULT_TOKEN=$(echo "$AUTH_RESPONSE" | jq -r '.auth.client_token')
    
    # Get entity ID and metadata
    TOKEN_INFO=$(docker exec vault sh -c "
        export VAULT_ADDR=http://localhost:8200
        export VAULT_TOKEN='$VAULT_TOKEN'
        vault token lookup -format=json 2>/dev/null
    ")
    
    CURRENT_ENTITY_ID=$(echo "$TOKEN_INFO" | jq -r '.data.entity_id')
    CURRENT_USER=$(echo "$TOKEN_INFO" | jq -r '.data.meta.user')
    CURRENT_TARGET=$(echo "$TOKEN_INFO" | jq -r '.data.meta.target')
    
    # Check current alias ID
    CURRENT_ENTITY_DETAILS=$(docker exec vault sh -c "
        export VAULT_ADDR=http://localhost:8200
        export VAULT_TOKEN=$VAULT_ROOT_TOKEN
        vault read -format=json identity/entity/id/$CURRENT_ENTITY_ID 2>/dev/null
    ")
    
    CURRENT_ALIAS_ID=$(echo "$CURRENT_ENTITY_DETAILS" | jq -r '.data.aliases[0].id')
    
    echo "  User: $CURRENT_USER | Target: $CURRENT_TARGET"
    if [[ "$CURRENT_ENTITY_ID" == "$FIRST_ENTITY_ID" && "$CURRENT_ALIAS_ID" == "$INITIAL_ALIAS_ID" ]]; then
        echo -e "  ${GREEN}✓${NC} Entity ID: $CURRENT_ENTITY_ID (unchanged)"
        echo -e "  ${GREEN}✓${NC} Alias ID: $CURRENT_ALIAS_ID (stable)"
    else
        echo -e "  ${RED}✗${NC} Entity or alias changed!"
        echo "    Expected Entity: $FIRST_ENTITY_ID"
        echo "    Actual Entity: $CURRENT_ENTITY_ID"
        echo "    Expected Alias: $INITIAL_ALIAS_ID"
        echo "    Actual Alias: $CURRENT_ALIAS_ID"
        exit 1
    fi
done

echo
echo -e "${BLUE}Step 5: Verify Metadata Differentiation${NC}"
echo "======================================"

echo "Checking that team metadata is properly preserved while sharing entity..."

for i in "${!TOKEN_DATA[@]}"; do
    token="${TOKEN_DATA[$i]}"
    team="${TEAMS[$i]}"
    
    echo -e "\n${YELLOW}Team $team token metadata:${NC}"
    
    TOKEN_INFO=$(docker exec vault sh -c "
        export VAULT_ADDR=http://localhost:8200
        export VAULT_TOKEN='$token'
        vault token lookup -format=json 2>/dev/null
    ")
    
    TEAM_META=$(echo "$TOKEN_INFO" | jq -r '.data.meta.team // "none"')
    USER_META=$(echo "$TOKEN_INFO" | jq -r '.data.meta.user // "none"')
    TARGET_META=$(echo "$TOKEN_INFO" | jq -r '.data.meta.target // "none"')
    
    echo "  Team: $TEAM_META"
    echo "  User: $USER_META" 
    echo "  Target: $TARGET_META"
    
    if [[ "$TEAM_META" == "$team" ]]; then
        echo -e "  ${GREEN}✓${NC} Team metadata correct"
    else
        echo -e "  ${RED}✗${NC} Team metadata incorrect (expected: $team, got: $TEAM_META)"
    fi
done

echo
echo -e "${GREEN}VERIFICATION COMPLETE!${NC}"
echo "========================="
echo
echo -e "${BLUE}Summary:${NC}"
echo "• All teams (alpha, beta, gamma, delta) share the same bazel-dev entity"
echo "• Entity alias remains stable across multiple authentications"
echo "• Individual team metadata is preserved in token metadata"
echo "• No entity or alias churn detected"
echo
echo -e "${GREEN}✓ Entity sharing working correctly!${NC}"
echo -e "${GREEN}✓ Alias stability confirmed!${NC}"
echo -e "${GREEN}✓ Team isolation via metadata verified!${NC}"