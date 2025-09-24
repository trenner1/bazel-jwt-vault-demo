#!/bin/bash
# Simple test script that uses Vault token

echo "Testing Vault integration..."
echo "VAULT_TOKEN is set: ${VAULT_TOKEN:+yes}"
echo "VAULT_TOKEN length: ${#VAULT_TOKEN}"

if [[ -n "$VAULT_TOKEN" ]]; then
    echo "Authentication successful - token available for Bazel build"
    
    # Test a simple Vault API call
    if command -v curl >/dev/null; then
        echo "Testing Vault token validity..."
        VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
        TOKEN_INFO=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
            "$VAULT_ADDR/v1/auth/token/lookup-self" 2>/dev/null || echo '{"data": null}')
        
        if echo "$TOKEN_INFO" | jq -e '.data.id' > /dev/null 2>&1; then
            echo "Vault token is valid and active"
            TTL=$(echo "$TOKEN_INFO" | jq -r '.data.ttl // 0')
            echo "   Token TTL: ${TTL}s"
        else
            echo "Vault token validation failed"
        fi
    fi
else
    echo "No VAULT_TOKEN found - authentication required"
    exit 1
fi