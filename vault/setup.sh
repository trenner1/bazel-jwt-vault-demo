#!/bin/sh
set -euo pipefail

: "${VAULT_ADDR:?set VAULT_ADDR}"
: "${VAULT_TOKEN:?set VAULT_TOKEN}"

# 1) Enable jwt auth if not already
if ! vault auth list -format=json | jq -e 'has("jwt/")' >/dev/null; then
  vault auth enable jwt
fi

# 2) Create Bazel-style dev policy with dynamic templating
vault policy write bazel-team /dev/stdin <<'POL'
# Team-scoped Bazel policy with dynamic path templating
# Based on Jenkins Vault POC pattern for logical license grouping

# KV v2: Pipeline-scoped read access - matches Jenkins POC pattern
# Dynamic path based on pipeline/job name from JWT metadata
path "kv/data/dev/apps/{{identity.entity.aliases.auth_jwt_*.metadata.pipeline}}/*" {
  capabilities = ["read"]
}

# KV v2: Team-pipeline-scoped secrets (additional team context)
path "kv/data/dev/apps/team-{{identity.entity.aliases.auth_jwt_*.metadata.team}}-pipeline/*" {
  capabilities = ["read"]
}

# KV v2: allow listing within dev scope
path "kv/metadata/dev/apps" {
  capabilities = ["list"]
}
path "kv/metadata/dev/apps/*" {
  capabilities = ["list"]
}

# Child token management (regular child tokens, not orphans)
path "auth/token/create" { 
  capabilities = ["update"] 
}

# Token introspection
path "auth/token/lookup-self" { 
  capabilities = ["update"] 
}
path "auth/token/revoke-self" { 
  capabilities = ["update"] 
}

# Capabilities check
path "sys/capabilities-self" { 
  capabilities = ["update"] 
}
POL

# 3) KV v2 engine at 'kv' path (matching Jenkins POC)
vault secrets enable -path=kv -version=2 kv || true

# Create team-pipeline-scoped secrets following Jenkins POC pattern
vault kv put kv/dev/apps/team-alpha-pipeline/frontend api_key="alpha-frontend-123" build_env="staging"
vault kv put kv/dev/apps/team-beta-pipeline/backend docker_registry="beta.registry.com" auth_token="beta-token-456"
vault kv put kv/dev/apps/team-gamma-pipeline/ml_pipeline model_path="/models/gamma" gpu_quota="4"

# Job-specific secrets (using job metadata from JWT)
vault kv put kv/dev/apps/frontend_app/config api_endpoint="https://api-staging.example.com" timeout="30s"
vault kv put kv/dev/apps/backend_service/config db_url="postgres://prod-db" cache_ttl="300"
vault kv put kv/dev/apps/ml_training/config gpu_cluster="cluster-1" model_version="v2.1"

echo "Created Jenkins-style team-scoped secrets:"
echo "  kv/dev/apps/team-alpha-pipeline/* (frontend team)"
echo "  kv/dev/apps/team-beta-pipeline/* (backend team)" 
echo "  kv/dev/apps/team-gamma-pipeline/* (ML team)"
echo "  kv/dev/apps/{job}/* (job-specific secrets)"

# 4) JWT auth config — point to Broker JWKS
vault write auth/jwt/config \
  oidc_discovery_url="" \
  jwks_url="http://broker:8081/.well-known/jwks.json" \
  default_role="dev-builds"

# 5) Role mapping — matches Jenkins POC exactly  
# Use bazel-specific entity names for team-based entities
vault write auth/jwt/role/bazel-builds \
  role_type="jwt" \
  user_claim="sub" \
  bound_audiences="vault-broker" \
  bound_issuer="http://localhost:8081" \
  claim_mappings="pipeline=pipeline,team=team,user=user,repo=repo,target=target,run_id=run_id" \
  policies="bazel-team" \
  token_ttl="5m" \
  token_max_ttl="15m"

echo "Vault JWT auth + role configured (Bazel team-based style)."
