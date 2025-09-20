#!/usr/bin/env bash
set -euo pipefail

: "${VAULT_ADDR:?set VAULT_ADDR}"
: "${VAULT_TOKEN:?set VAULT_TOKEN}"

# 1) Enable jwt auth if not already
if ! vault auth list -format=json | jq -e 'has("jwt/")' >/dev/null; then
  vault auth enable jwt
fi

# 2) Create team-based policy with dynamic templating
vault policy write bazel-team /dev/stdin <<'POL'
# Team-scoped Bazel policy with dynamic path templating
# Based on Jenkins Vault POC pattern for logical license grouping

# KV v2: team and pipeline-scoped read access
path "secret/data/bazel/{{identity.entity.aliases.auth_jwt_*.metadata.team}}/*" {
  capabilities = ["read"]
}

# KV v2: pipeline-specific secrets
path "secret/data/bazel/{{identity.entity.aliases.auth_jwt_*.metadata.team}}/{{identity.entity.aliases.auth_jwt_*.metadata.pipeline}}/*" {
  capabilities = ["read"]
}

# KV v2: allow listing within team scope
path "secret/metadata/bazel/{{identity.entity.aliases.auth_jwt_*.metadata.team}}" {
  capabilities = ["list"]
}
path "secret/metadata/bazel/{{identity.entity.aliases.auth_jwt_*.metadata.team}}/*" {
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

# 3) KV v2 engine & team-based demo secrets
vault secrets enable -path=secret -version=2 kv || true

# Create team-scoped secrets following the pattern
vault kv put secret/bazel/team-alpha/app_build api_key="alpha-api-key-123" db_url="postgres://alpha-db"
vault kv put secret/bazel/team-beta/service_deploy docker_registry="beta.registry.com" auth_token="beta-token-456"
vault kv put secret/bazel/team-gamma/ml_pipeline model_path="/models/gamma" gpu_quota="4"

# General team secrets
vault kv put secret/bazel/team-alpha/shared build_env="staging" team_slack="#alpha-builds"
vault kv put secret/bazel/team-beta/shared build_env="production" team_slack="#beta-deploys"

echo "Created team-scoped secrets:"
echo "  secret/bazel/team-alpha/* (frontend team)"
echo "  secret/bazel/team-beta/* (backend team)"
echo "  secret/bazel/team-gamma/* (ML team)"

# 4) JWT auth config — point to Broker JWKS
vault write auth/jwt/config \
  oidc_discovery_url="" \
  jwks_url="http://broker:8081/.well-known/jwks.json" \
  default_role="bazel-builds"

# 5) Role mapping — map claims → policies & validate iss/aud
# Use team-based entity model: sub=team name for logical grouping
vault write auth/jwt/role/bazel-builds \
  role_type="jwt" \
  user_claim="pipeline" \
  bound_audiences="vault-broker" \
  bound_issuer="http://localhost:8081" \
  claim_mappings="repo=repo,target=target,run_id=run_id,team=team,user=user,pipeline=pipeline" \
  groups_claim="groups" \
  policies="bazel-team" \
  token_ttl="5m" \
  token_max_ttl="15m"

echo "Vault JWT auth + role configured."
