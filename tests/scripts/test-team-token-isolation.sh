#!/bin/bash
# Test team-specific token creation security

echo "Testing Team Token Creation Isolation..."

# Prerequisites check
echo "Checking prerequisites..."

# Check if VAULT_TOKEN is set
if [ -z "$VAULT_TOKEN" ]; then
    echo "VAULT_TOKEN not set. Please set a root or admin token first."
    echo "   Example: export VAULT_TOKEN=your-root-token"
    exit 1
fi

# Check if VAULT_ADDR is set
if [ -z "$VAULT_ADDR" ]; then
    echo "VAULT_ADDR not set. Setting to default..."
    export VAULT_ADDR=http://localhost:8200
fi

# Check if broker is running
if ! curl -s -f http://localhost:8081/health > /dev/null; then
    echo "Broker service not available at http://localhost:8081"
    echo "   Please start services with: docker-compose up -d"
    exit 1
fi

echo "Prerequisites checked"

# Step 1: Check if token roles exist
echo "Checking token role configuration..."
roles_available=()

for role in "mobile-team-token" "backend-team-token" "frontend-team-token"; do
    if vault read auth/token/roles/$role > /dev/null 2>&1; then
        roles_available+=($role)
        echo "Role $role exists"
    else
        echo "Role $role missing"
    fi
done

if [ ${#roles_available[@]} -eq 0 ]; then
    echo "No token roles found. Please run vault setup first."
    exit 1
fi

# Step 2: Interactive authentication to get team tokens
echo ""
echo "Team Token Creation Test - Interactive Setup Required"
echo "========================================================="
echo ""

# Check if we already have tokens set
if [ -n "$MOBILE_TOKEN" ]; then
    echo "MOBILE_TOKEN found, proceeding with tests..."
    
    # Test 1: Mobile team token restrictions (restricted use tokens cannot create children)
    echo ""
    echo "Test 1: Mobile team token child creation (testing use restrictions)..."
    mobile_create_result=$(VAULT_TOKEN=$MOBILE_TOKEN vault write auth/token/create/mobile-team-token ttl=1h -format=json 2>&1)
    if [[ $? -eq 0 ]]; then
        echo "Mobile team can create mobile team tokens"
        # Extract the token for cleanup
        mobile_child_token=$(echo "$mobile_create_result" | jq -r '.auth.client_token // empty')
    elif [[ $mobile_create_result == *"restricted use token cannot generate child tokens"* ]]; then
        echo "Mobile team token correctly restricted (cannot create child tokens)"
        echo "   This is EXCELLENT security: restricted use tokens prevent token proliferation"
    else
        echo "Mobile team failed to create mobile team tokens"
        echo "   Error: $mobile_create_result"
    fi

    # Test 2: Mobile team should NOT be able to create backend team tokens
    echo ""
    echo "Test 2: Mobile team creating backend team token (should fail)..."
    backend_create_result=$(VAULT_TOKEN=$MOBILE_TOKEN vault write auth/token/create/backend-team-token ttl=1h 2>&1)
    if [[ $? -ne 0 ]] && [[ $backend_create_result == *"permission denied"* ]]; then
        echo "Mobile team correctly denied creating backend team tokens"
        echo "   Security boundary working as expected!"
    else
        echo "SECURITY ISSUE: Mobile team can create backend team tokens"
        echo "   Result: $backend_create_result"
    fi

    # Test 3: Test secret access boundaries
    echo ""
    echo "Test 3: Testing secret access boundaries..."
    
    # Mobile team should access mobile secrets
    mobile_secret_test=$(VAULT_TOKEN=$MOBILE_TOKEN vault kv get kv/dev/mobile/config 2>&1)
    if [[ $? -eq 0 ]]; then
        echo "Mobile team can access mobile secrets"
    else
        echo "Mobile secrets not found (expected in test env)"
    fi
    
    # Mobile team should NOT access backend secrets
    backend_secret_test=$(VAULT_TOKEN=$MOBILE_TOKEN vault kv get kv/dev/backend/config 2>&1)
    if [[ $? -ne 0 ]] && [[ $backend_secret_test == *"permission denied"* ]]; then
        echo "Mobile team correctly denied access to backend secrets"
    else
        echo "SECURITY ISSUE: Mobile team can access backend secrets"
    fi

    # Cleanup created tokens
    if [ -n "$mobile_child_token" ]; then
        echo ""
        echo "Cleaning up test tokens..."
        VAULT_TOKEN=$VAULT_TOKEN vault token revoke $mobile_child_token 2>/dev/null
        echo "Test tokens cleaned up"
    fi

else
    echo "No MOBILE_TOKEN found. This test requires a team-specific token."
    echo ""
    echo "Step-by-step authentication guide:"
    echo ""
    echo "1. Start the PKCE authentication flow:"
    echo "   curl -X POST http://localhost:8081/cli/start"
    echo ""
    echo "2. Copy the 'auth_url' from the response and open it in browser"
    echo ""
    echo "3. Complete Okta authentication as a MOBILE team member"
    echo ""
    echo "4. After redirect, copy the 'session_id' from the callback page"
    echo ""
    echo "5. Get the team token:"
    echo "   export SESSION_ID=your-session-id"
    echo "   export MOBILE_TOKEN=\$(./tools/bazel-auth-simple --session-id \$SESSION_ID --token-only)"
    echo ""
    echo "6. Re-run this test:"
    echo "   MOBILE_TOKEN=\$MOBILE_TOKEN ./tests/scripts/test-team-token-isolation.sh"
    echo ""
    echo "Quick start (generates auth URL for you):"
    echo ""
    read -p "Generate authentication URL now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "Generating authentication URL..."
        auth_response=$(curl -s -X POST http://localhost:8081/cli/start)
        if [[ $? -eq 0 ]]; then
            auth_url=$(echo "$auth_response" | jq -r '.auth_url // empty')
            state=$(echo "$auth_response" | jq -r '.state // empty')
            
            if [[ -n "$auth_url" ]] && [[ "$auth_url" != "null" ]]; then
                echo ""
                echo "Authentication URL:"
                echo "$auth_url"
                echo ""
                echo "Instructions:"
                echo "1. Open the URL above in your browser"
                echo "2. Complete Okta authentication as a mobile team member"
                echo "3. After successful auth, look for 'session_id' in the response"
                echo "4. Run: export SESSION_ID=your-session-id"
                echo "5. Run: export MOBILE_TOKEN=\$(./tools/bazel-auth-simple --session-id \$SESSION_ID --token-only)"
                echo "6. Re-run this test script"
            else
                echo "Failed to generate auth URL"
                echo "Response: $auth_response"
            fi
        else
            echo "Failed to connect to broker service"
        fi
    fi
    
    exit 1
fi

echo ""
echo "Team token creation isolation test completed"