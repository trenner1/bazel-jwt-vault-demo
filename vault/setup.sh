#!/bin/bash

# Bazel JWT Vault Demo - Broker-based JWT Setup Script
# This script configures HashiCorp Vault for broker-generated JWT authentication
# with team-based entity isolation for Bazel builds.
#
# Architecture Overview:
# - Authentication Broker: Generates team-based JWT tokens with RSA signing
# - Vault JWT Auth: Validates broker-generated tokens using public key
# - Team Entities: One entity per team for stable aliases and shared access
# - User Context: Multi-team users select context via broker interface

set -euo pipefail

# Load environment variables from .env file if it exists
if [[ -f .env ]]; then
    echo "Loading environment variables from .env file..."
    # Export variables from .env, ignoring comments and empty lines
    export $(grep -E '^[A-Z_]+=.*' .env | xargs)
elif [[ -f ../.env ]]; then
    echo "Loading environment variables from ../.env file..."
    export $(grep -E '^[A-Z_]+=.*' ../.env | xargs)
else
    echo "WARNING: No .env file found. Please ensure environment variables are set."
fi

# Check required environment variables
if [[ -z "$VAULT_ADDR" ]]; then
    echo "Setting default VAULT_ADDR=http://localhost:8200"
    export VAULT_ADDR="http://localhost:8200"
else
    # If VAULT_ADDR uses docker service name, convert to localhost for host execution
    if [[ "$VAULT_ADDR" == *"vault:8200"* ]]; then
        echo "Converting Docker service address to localhost"
        export VAULT_ADDR="http://localhost:8200"
    fi
fi

if [[ -z "$VAULT_TOKEN" ]]; then
    if [[ -n "$VAULT_ROOT_TOKEN" ]]; then
        echo "Using VAULT_ROOT_TOKEN as VAULT_TOKEN"
        export VAULT_TOKEN="$VAULT_ROOT_TOKEN"
    else
        echo "Error: Neither VAULT_TOKEN nor VAULT_ROOT_TOKEN environment variable is set"
        exit 1
    fi
fi

if [[ -z "$OKTA_DOMAIN" ]]; then
    echo "Warning: OKTA_DOMAIN not set, using placeholder"
    OKTA_DOMAIN="dev-example.okta.com"
fi

if [[ -z "$OKTA_CLIENT_ID" ]]; then
    echo "Warning: OKTA_CLIENT_ID not set, using placeholder"
    OKTA_CLIENT_ID="vault-demo-client"
fi

if [[ -z "$OKTA_CLIENT_SECRET" ]]; then
    echo "Warning: OKTA_CLIENT_SECRET not set, using placeholder"
    OKTA_CLIENT_SECRET="demo-secret"
fi

echo " Setting up Vault for Bazel JWT Demo with Broker-based Authentication..."
echo "Vault Address: $VAULT_ADDR"
echo "Okta Domain: $OKTA_DOMAIN (for broker authentication)"
echo "Client ID: $OKTA_CLIENT_ID (for broker authentication)"

# 1) Enable KV v2 secrets engine
echo " Enabling KV v2 secrets engine..."
vault secrets enable -version=2 -path=kv kv 2>/dev/null || echo "KV engine already enabled"

# 2) Create team-specific policies for fine-grained access control
echo " Creating team-specific policies..."

# Base policy - minimal access for all authenticated users
vault policy write bazel-base - <<EOF
# Base policy for all Bazel users
path "kv/metadata" {
  capabilities = ["list"]
}

path "kv/data/dev/shared/*" {
  capabilities = ["read"]
}

# Allow reading own user-specific secrets
path "kv/data/dev/users/{{identity.entity.aliases.auth_oidc_*.name}}/*" {
  capabilities = ["read", "create", "update"]
}
EOF

# Mobile team policy - access to mobile-specific secrets
vault policy write bazel-mobile-team - <<EOF
# Mobile team access
path "kv/data/dev/mobile/*" {
  capabilities = ["read"]
}

path "kv/metadata/dev/mobile/*" {
  capabilities = ["read", "list"]
}

# Legacy pipeline paths for backward compatibility
path "kv/data/dev/apps/team-mobile-team-pipeline/*" {
  capabilities = ["read"]
}
EOF

# Backend team policy - access to backend-specific secrets
vault policy write bazel-backend-team - <<EOF
# Backend team access
path "kv/data/dev/backend/*" {
  capabilities = ["read"]
}

path "kv/metadata/dev/backend/*" {
  capabilities = ["read", "list"]
}

# Legacy pipeline paths for backward compatibility
path "kv/data/dev/apps/team-backend-team-pipeline/*" {
  capabilities = ["read"]
}
EOF

# Frontend team policy - access to frontend-specific secrets
vault policy write bazel-frontend-team - <<EOF
# Frontend team access
path "kv/data/dev/frontend/*" {
  capabilities = ["read"]
}

path "kv/metadata/dev/frontend/*" {
  capabilities = ["read", "list"]
}

# Legacy pipeline paths for backward compatibility
path "kv/data/dev/apps/team-frontend-team-pipeline/*" {
  capabilities = ["read"]
}
EOF

echo "Created policies:"
echo "   bazel-base: shared secrets + user-specific paths"
echo "   bazel-mobile-team: mobile development secrets"
echo "   bazel-backend-team: backend development secrets"
echo "   bazel-frontend-team: frontend development secrets"

# 3) Create team-specific secrets with realistic content
echo " Creating team-specific secrets..."

# Shared secrets (accessible to all teams)
vault kv put kv/dev/shared/common \
  app_version="1.0.0" \
  environment="development" \
  shared_config="common-settings"

# Mobile team secrets
vault kv put kv/dev/mobile/ios \
  bundle_id="com.company.bazelapp" \
  provisioning_profile="iOS_Development_Profile" \
  code_signing_identity="iPhone Developer" \
  app_store_connect_key="mobile-asc-key-123"

vault kv put kv/dev/mobile/android \
  package_name="com.company.bazelapp" \
  keystore_alias="debug_key" \
  play_store_key="mobile-play-key-456"

vault kv put kv/dev/mobile/shared \
  api_endpoint="https://mobile-api.company.com" \
  analytics_key="mobile-analytics-789" \
  feature_flags="mobile-features-abc"

# Backend team secrets
vault kv put kv/dev/backend/database \
  host="backend-db.company.com" \
  username="bazel_backend_user" \
  password="backend-db-secret-123" \
  connection_pool_size="10"

vault kv put kv/dev/backend/api \
  jwt_secret="backend-jwt-secret-456" \
  redis_url="redis://backend-cache.company.com:6379" \
  external_api_key="backend-external-789"

vault kv put kv/dev/backend/services \
  message_queue_url="amqp://backend-mq.company.com" \
  monitoring_token="backend-monitor-abc" \
  deployment_key="backend-deploy-def"

# Frontend team secrets
vault kv put kv/dev/frontend/build \
  cdn_url="https://frontend-cdn.company.com" \
  asset_hash_salt="frontend-hash-123" \
  build_optimization_key="frontend-opt-456"

vault kv put kv/dev/frontend/deployment \
  s3_bucket="frontend-assets-bucket" \
  cloudfront_distribution="E1234567890ABC" \
  deployment_webhook="frontend-deploy-789"

vault kv put kv/dev/frontend/analytics \
  google_analytics_id="GA-FRONTEND-123" \
  mixpanel_token="frontend-mixpanel-456" \
  sentry_dsn="frontend-sentry-789"

# Legacy paths for backward compatibility
vault kv put kv/dev/apps/team-mobile-team-pipeline/legacy \
  legacy_mobile_key="mobile-legacy-123"
vault kv put kv/dev/apps/team-backend-team-pipeline/legacy \
  legacy_backend_key="backend-legacy-456"  
vault kv put kv/dev/apps/team-frontend-team-pipeline/legacy \
  legacy_frontend_key="frontend-legacy-789"

echo "Created team-specific secrets:"
echo "   Mobile team: kv/dev/mobile/* (iOS, Android, shared API)"
echo "   Backend team: kv/dev/backend/* (database, API, external services)"
echo "   Frontend team: kv/dev/frontend/* (build, deployment, analytics)"
echo "   Legacy paths: kv/dev/apps/team-*-pipeline/* (backward compatibility)"

# 4) Configure broker-based JWT authentication
echo " Configuring broker-based JWT authentication..."

# Enable JWT auth method
vault auth enable jwt 2>/dev/null || echo "JWT auth method already enabled"

# Configure JWT auth to use broker's public key for token verification
# The broker generates RSA-signed JWTs with team names as subjects

# Get the path to the JWT public key
JWT_PUBLIC_KEY_PATH=""
if [[ -f "broker/jwt_signing_key.pub" ]]; then
    JWT_PUBLIC_KEY_PATH="broker/jwt_signing_key.pub"
elif [[ -f "../broker/jwt_signing_key.pub" ]]; then
    JWT_PUBLIC_KEY_PATH="../broker/jwt_signing_key.pub"
else
    echo "Error: JWT public key not found. Please run ./scripts/generate-jwt-keys.sh first"
    exit 1
fi

echo "Using JWT public key from: $JWT_PUBLIC_KEY_PATH"
vault write auth/jwt/config \
  bound_issuer="bazel-auth-broker" \
  jwt_validation_pubkeys=@${JWT_PUBLIC_KEY_PATH}

# 5) Create team-specific JWT roles
echo " Configuring team-specific JWT roles..."

# Team-based JWT authentication creates stable entities per team
# Each role maps to a specific team with consistent subject claims

# Mobile team role (JWT subject: "mobile-team")
vault write auth/jwt/role/mobile-team \
  bound_audiences="bazel-vault" \
  bound_subject="mobile-team" \
  user_claim="sub" \
  role_type="jwt" \
  policies="bazel-mobile-team,bazel-base" \
  ttl="2h" \
  max_ttl="4h"

# Backend team role (JWT subject: "backend-team")
vault write auth/jwt/role/backend-team \
  bound_audiences="bazel-vault" \
  bound_subject="backend-team" \
  user_claim="sub" \
  role_type="jwt" \
  policies="bazel-backend-team,bazel-base" \
  ttl="2h" \
  max_ttl="4h"

# Frontend team role (JWT subject: "frontend-team")
vault write auth/jwt/role/frontend-team \
  bound_audiences="bazel-vault" \
  bound_subject="frontend-team" \
  user_claim="sub" \
  role_type="jwt" \
  policies="bazel-frontend-team,bazel-base" \
  ttl="2h" \
  max_ttl="4h"

# DevOps team role (JWT subject: "devops-team")
vault write auth/jwt/role/devops-team \
  bound_audiences="bazel-vault" \
  bound_subject="devops-team" \
  user_claim="sub" \
  role_type="jwt" \
  policies="bazel-backend-team,bazel-frontend-team,bazel-mobile-team,bazel-base" \
  ttl="4h" \
  max_ttl="8h"

# Base team role (fallback for basic access)
vault write auth/jwt/role/base-team \
  bound_audiences="bazel-vault" \
  user_claim="sub" \
  role_type="jwt" \
  policies="bazel-base" \
  ttl="1h" \
  max_ttl="2h"

# 6) Enable identity secrets engine for team-based entity management
echo " Configuring identity management for team-based entities..."
vault secrets enable -path=identity identity 2>/dev/null || echo "Identity engine already enabled"

# 7) Create identity groups for team-based access control
echo " Creating identity groups (entities will be created dynamically by broker authentication)..."

# Note: With broker-based JWT authentication, entities are created automatically
# when users authenticate with team-specific JWTs. Each team gets one stable entity
# with consistent aliases, enabling shared access and stable identity management.

# Mobile developers group
vault write identity/group name="mobile-developers" \
  policies="bazel-base,bazel-mobile-team" \
  metadata=team="mobile" \
  metadata=description="Mobile development team - entities created via mobile-team JWT"

# Backend developers group  
vault write identity/group name="backend-developers" \
  policies="bazel-base,bazel-backend-team" \
  metadata=team="backend" \
  metadata=description="Backend development team - entities created via backend-team JWT"

# Frontend developers group
vault write identity/group name="frontend-developers" \
  policies="bazel-base,bazel-frontend-team" \
  metadata=team="frontend" \
  metadata=description="Frontend development team - entities created via frontend-team JWT"

# DevOps team group (broader access)
vault write identity/group name="devops-team" \
  policies="bazel-base,bazel-backend-team,bazel-frontend-team,bazel-mobile-team" \
  metadata=team="devops" \
  metadata=description="DevOps team with cross-functional access - entities created via devops-team JWT"

echo ""
echo " Vault setup complete for broker-based JWT authentication!"
echo ""
echo " Configuration Summary:"
echo "   Auth Method: Broker-generated JWT tokens"
echo "   Token Signing: RSA 2048-bit key pair (broker-managed)"
echo "   User Authentication: Okta OIDC (via broker)"
echo "   Entity Management: Team-based with stable aliases"
echo ""
echo " Authentication Flow:"
echo "  1. User authenticates with broker via Okta OIDC"
echo "  2. Broker determines user's team memberships"
echo "  3. User selects team context (if multiple teams)"
echo "  4. Broker generates team-specific JWT token"
echo "  5. Vault validates JWT and creates/reuses team entity"
echo ""
echo " Team Roles (JWT Subjects):"
echo "   mobile-team: JWT sub='mobile-team' → mobile secrets"
echo "   backend-team: JWT sub='backend-team' → backend secrets"
echo "   frontend-team: JWT sub='frontend-team' → frontend secrets"
echo "   devops-team: JWT sub='devops-team' → all secrets"
echo "   base-team: Fallback role → shared secrets only"
echo ""
echo "Secret Paths:"
echo "   kv/dev/shared/* - Accessible to all teams"
echo "   kv/dev/mobile/* - Mobile team only"
echo "   kv/dev/backend/* - Backend team only"
echo "   kv/dev/frontend/* - Frontend team only"
echo ""
echo " Next Steps:"
echo "  1. Deploy authentication broker with:"
echo "     - RSA key pair for JWT signing"
echo "     - Okta OIDC configuration"
echo "     - Team context selection interface"
echo "  2. Configure Okta app with broker redirect URIs"
echo "  3. Test team-based JWT authentication"
echo "  4. Verify entity isolation and stable aliases"