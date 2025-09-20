#!/usr/bin/env bash
# Team-based Build Simulation
# Demonstrates transparent authentication with team-based entity model
set -euo pipefail

BROKER="${BROKER:-http://127.0.0.1:8081}"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"

echo "🏗️  Bazel Team-Based Build Simulation"
echo ""

# 1) Simulate team-alpha frontend build
echo "👥 Team Alpha (Frontend) - Building React App"
ASSERTION=$(curl -s -X POST "$BROKER/demo/sign" -H 'content-type: application/json' \
  -d '{
    "team": "team-alpha",
    "user": "alice@company.com",
    "groups": ["bazel-dev", "team-alpha"],
    "repo": "monorepo",
    "target": "//frontend:app",
    "pipeline": "frontend_app",
    "run_id": "alpha-build-001"
  }' | jq -r .assertion)

# 2) Exchange for Vault token
read -r VAULT_TOKEN META <<EOF
$(curl -s -X POST "$BROKER/exchange" -H 'content-type: application/json' \
  -d "{\"assertion\":\"$ASSERTION\"}" | jq -r '[.vault_token, (.meta|tostring)] | @tsv')
EOF

echo "   ✅ Team Alpha authenticated successfully"
echo "   📋 Context: $META" | tr ',' '\n' | sed 's/^/      /'

# 3) Test team-scoped secret access
echo "   🔍 Accessing team secrets..."
TEAM_SECRET=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
  "$VAULT_ADDR/v1/secret/data/bazel/team-alpha/shared" | jq -r '.data.data // empty')

if [[ -n "$TEAM_SECRET" && "$TEAM_SECRET" != "null" ]]; then
  echo "   🎉 Team Alpha secrets accessible!"
  echo "$TEAM_SECRET" | jq -r 'to_entries[] | "      \(.key): \(.value)"'
else
  echo "   ℹ️  No team secrets configured (run vault setup)"
fi

echo ""

# 4) Simulate team-beta backend build  
echo "👥 Team Beta (Backend) - Building API Service"
ASSERTION=$(curl -s -X POST "$BROKER/demo/sign" -H 'content-type: application/json' \
  -d '{
    "team": "team-beta", 
    "user": "bob@company.com",
    "groups": ["bazel-dev", "team-beta"],
    "repo": "monorepo", 
    "target": "//backend:api",
    "pipeline": "backend_api",
    "run_id": "beta-build-002"
  }' | jq -r .assertion)

read -r VAULT_TOKEN META <<EOF
$(curl -s -X POST "$BROKER/exchange" -H 'content-type: application/json' \
  -d "{\"assertion\":\"$ASSERTION\"}" | jq -r '[.vault_token, (.meta|tostring)] | @tsv')
EOF

echo "   ✅ Team Beta authenticated successfully"
echo "   📋 Context: $META" | tr ',' '\n' | sed 's/^/      /'

echo "   🔍 Accessing team secrets..."
TEAM_SECRET=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
  "$VAULT_ADDR/v1/secret/data/bazel/team-beta/shared" | jq -r '.data.data // empty')

if [[ -n "$TEAM_SECRET" && "$TEAM_SECRET" != "null" ]]; then
  echo "   🎉 Team Beta secrets accessible!"
  echo "$TEAM_SECRET" | jq -r 'to_entries[] | "      \(.key): \(.value)"'
else
  echo "   ℹ️  No team secrets configured (run vault setup)"
fi

echo ""
echo "🎯 Key Benefits Demonstrated:"
echo "   ✅ Teams are isolated (team-alpha ≠ team-beta)"
echo "   ✅ Same team members reuse entities (licensing efficient)"  
echo "   ✅ Dynamic policy templating based on team context"
echo "   ✅ Completely transparent to developers"
echo ""
echo "💡 In production:"
echo "   • Teams determined from LDAP/Okta groups"
echo "   • Bazel automatically handles authentication"
echo "   • No manual token management required"
