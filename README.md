# Bazel JWT Vault Demo - Team-Based Entity Model

A demonstration of **team-based JWT authentication** with HashiCorp Vault, implementing a licensing-efficient entity model where team members share entities based on the [Jenkins Vault POC](https://github.com/trenner1/jenkins-vault-poc) pattern.

## What This POC Proves

- **Zero Entity Churning**: Same entity/alias reused across team member builds
- **Logical Workload Grouping**: Entity count scales with teams, organizing identical workloads efficiently  
- **Individual Attribution**: Child tokens contain individual developer metadata while sharing team entities
- **Secure Team Isolation**: Teams cannot access other teams' secrets or entities
- **Scalable Architecture**: Supports organizations with multiple development teams and large monorepos

**Verified**: Real JWT authentication with team-specific entity creation and same-team entity sharing - **proven licensing efficiency with no churning detected**.

## Environment Variables

The system uses environment variables for secure configuration. Copy `.env.example` to `.env` and configure:

| Variable | Description | Example | Required |
|----------|-------------|---------|-----------|
| `VAULT_ROOT_TOKEN` | Vault root token for admin operations | `hvs.xxxxxxxxxxxx` | Yes |
| `VAULT_ADDR` | Vault server address | `http://localhost:8200` | Yes |
| `BROKER_URL` | JWT broker service URL | `http://localhost:8081` | Yes |
| `ISSUER` | JWT issuer claim | `http://localhost:8081` | Yes |

> **Security Note**: The `.env` file is excluded from Git via `.gitignore`. Never commit secrets to version control.

## Architecture Overview

### Team-Based Entity Model

```
Team Alpha (bazel-alpha)  →  Entity: bazel-alpha  →  Secrets: secret/data/bazel/alpha/*
├── alice.smith          
├── bob.jones            
└── carol.wilson         

Team Beta (bazel-beta)    →  Entity: bazel-beta   →  Secrets: secret/data/bazel/beta/*
├── dave.brown           
├── eve.taylor           
└── frank.moore          

Team Gamma (bazel-gamma)  →  Entity: bazel-gamma  →  Secrets: secret/data/bazel/gamma/*
├── grace.davis          
└── henry.clark          
```

**Benefits:**
- **No Churning**: Same entity reused by all team members (bazel-alpha, bazel-beta, etc.)
- **Logical Organization**: Entity count = number of teams (groups identical workloads efficiently)
- **Individual Attribution**: Child tokens track individual developers while sharing team entities
- **Secure Isolation**: Teams cannot access other teams' secrets or entities
- **Scalable**: Supports organizations with multiple teams and large monorepos

```
┌─────────────┐    JWT          ┌─────────────┐   Vault Token    ┌─────────────┐
│ Bazel Build │ ──────────────> │ JWT Broker  │ ───────────────> │    Vault    │
│ (Team Alpha)│  (team context) │             │  (team-scoped)   │ Team Secrets│
└─────────────┘                 └─────────────┘                  └─────────────┘
      ↑                                ↓                                  
  Team Detection                 Entity: bazel-alpha                      
  via Git/Env                   (shared by team)                          
```

## Comparison with Other Approaches

| Approach | Entity Count | Vault Licensing | Team Isolation | Management Complexity |
|----------|-------------|----------------|----------------|---------------------|
| **Per Developer** | 1 per developer | High | Excellent | Medium |
| **Single Shared** | 1 total | Minimal | None | Low |
| **Per Team (This POC)** | 1 per team | Low | Good | Medium |

### Why Team-Based Entities are Optimal:

- **Logical Grouping**: Groups identical workloads by team function rather than individual identity
- **Security**: Natural isolation boundaries align with organizational structure  
- **Scalability**: Linear growth with workload types rather than individual users
- **Management**: Easier to audit and manage team-based access patterns

## Project Structure

```
bazel-jwt-vault-demo/
├── broker/                    # FastAPI JWT broker service
│   ├── app.py                 # Main broker application (team-based entities)
│   ├── gen_keys.py            # RSA key generation utility
│   ├── requirements.txt       # Python dependencies
│   ├── jwks.json              # Public keys (JWKS format)
│   └── signer_keys.json       # Private keys (development only)
├── client/                    # Demo client simulation
│   └── build_sim.sh           # Team-based build workflow demo
├── vault/                     # Vault configuration
│   └── setup.sh               # Vault setup with team policies
├── docker-compose.yml         # Container orchestration
├── start-broker.sh            # Broker startup script
├── verify_entity_sharing.sh   # Entity sharing verification script
├── .env.example               # Environment template
└── README.md                  # This file
```

## Prerequisites

- **Docker** and **Docker Compose**
- **HashiCorp Vault** (existing instance)
- **curl** and **jq** (for testing - included in Docker images)
- **Git** (for team detection)

## Quick Start

### Environment Setup

1. **Configure Environment Variables**:
   ```bash
   # Copy environment template
   cp .env.example .env
   
   # Edit .env with your actual values
   vim .env
   
   # Optional: Remove any existing virtual environment (not needed for Docker)
   rm -rf .venv
   ```

   Required environment variables:
   ```bash
   # Vault Configuration
   VAULT_ROOT_TOKEN=your-vault-root-token-here
   VAULT_ADDR=http://localhost:8200
   
   # Broker Configuration  
   BROKER_URL=http://localhost:8081
   ISSUER=http://localhost:8081
   ```

   > **Security**: Never commit the `.env` file to Git. It contains sensitive tokens.

### Docker Deployment (Recommended)

2. **Start the Services**:
   ```bash
   # Build and start the broker (no virtual environment needed)
   docker-compose up -d
   
   # Configure Vault with team policies
   docker-compose run --rm vault-setup
   ```

3. **Test Team-Based Authentication**:
   ```bash
   # Verify team entity sharing
   ./verify_entity_sharing.sh
   
   # Output should show:
   # Team Alpha Entity: entity_12345
   # Team Beta Entity: entity_67890  
   # Team members share same entities
   ```

### Local Development (Alternative)

For local development without Docker (requires local Python setup):

1. **Install Dependencies**:
   ```bash
   # Ensure Python 3.11+ is installed
   cd broker && pip install -r requirements.txt && cd ..
   ```

2. **Start the JWT Broker**:
   ```bash
   # Load environment variables
   source .env
   
   # Start the broker directly (requires dependencies installed)
   cd broker && python -m uvicorn app:app --host 0.0.0.0 --port 8081
   ```

3. **Configure Vault**:
   ```bash
   # Run the Vault setup script
   ./vault/setup.sh
   ```

4. **Test Team Authentication**:
   ```bash
   # Test team entity model
   ./verify_entity_sharing.sh
   ```

> **Note**: Docker deployment is recommended as it handles all dependencies automatically.

### Verify Team Entity Model

```bash
# Verify team-based entity sharing (logical workload grouping)
./verify_entity_sharing.sh

# This proves:
# - Different teams get different entities (bazel-alpha, bazel-beta)  
# - Same team members share the same entity (no churning)
# - Individual metadata preserved in child tokens
```

## API Endpoints

### JWT Broker (`http://localhost:8081`)

#### `GET /.well-known/jwks.json`
Returns the public key set for JWT verification.

#### `POST /demo/sign`
Development endpoint that signs demo JWTs with team-specific subjects.

**Request:**
```json
{
  "team": "alpha",
  "user": "alice@company.com",
  "repo": "monorepo",
  "target": "//frontend:app",
  "pipeline": "frontend_app",
  "run_id": "build-123"
}
```

**Response:**
```json
{
  "assertion": "eyJ0eXAiOiJKV1Q...",
  "claims": {
    "iss": "http://localhost:8081",
    "aud": "vault-broker",
    "sub": "bazel-alpha",
    "team": "alpha",
    "user": "alice@company.com",
    "pipeline": "frontend_app",
    "target": "//frontend:app",
    "exp": 1234568790,
    "iat": 1234567890
  }
}
```

#### `POST /exchange`
Exchanges a signed JWT for a constrained Vault token.

**Request:**
```json
{
  "assertion": "eyJ0eXAiOiJKV1Q..."
}
```

**Response:**
```json
{
  "vault_token": "hvs.CAESIJ...",
  "meta": {
    "repo": "monorepo",
    "target": "//frontend:app",
    "team": "alpha",
    "pipeline": "frontend_app",
    "user": "alice@company.com",
    "run_id": "build-123",
    "entity_id": "entity_12345",
    "issued_by": "broker"
  }
}
```

## Key Management

### Generate New Keys

```bash
# Using Python directly
cd broker && python gen_keys.py

# Using Docker
docker-compose run --rm broker python gen_keys.py
```

This generates:
- `broker/jwks.json` - Public keys in JWKS format (used by Vault)
- `broker/signer_keys.json` - Private keys (development only)

### Key Security Notes

- **Development**: Private keys are stored in `signer_keys.json` for demo purposes
- **Production**: Use proper key management (HSMs, Vault Transit, etc.)
- **Rotation**: Regenerate keys periodically and update Vault configuration

## Security Best Practices

### Environment Variable Management

**DO:**
- Use `.env` files for local development
- Use Docker secrets or Kubernetes secrets in production
- Rotate Vault tokens regularly
- Use specific Vault policies with minimal required permissions

❌ **DON'T:**
- Commit `.env` files to Git (excluded via `.gitignore`)
- Use root tokens in production (use role-based tokens)
- Share environment files between environments
- Log sensitive environment variables

### Vault Token Security

This demo uses **regular child tokens** (not orphan tokens) for better security:

```bash
# Regular child tokens (recommended)
vault token create -policy=bazel-policy -ttl=24h

# Orphan tokens (avoid in production)
vault token create -policy=bazel-policy -orphan
```

**Benefits of regular child tokens:**
- Automatic cleanup when parent expires
- Better audit trail
- Proper token hierarchy

### Production Considerations

- **Network Security**: Use TLS for all Vault communication
- **Token TTL**: Short-lived tokens (1-24 hours)
- **Policy Scope**: Team-specific policies with minimal privileges
- **Monitoring**: Alert on unusual token creation patterns
- **Access Control**: Restrict broker service network access

## Security Model

### JWT Claims Structure (Team-Based Model)
Required claims in build JWTs:
```json
{
  "iss": "http://localhost:8081",       // Broker issuer
  "sub": "bazel-alpha",                 // Team-specific entity identifier
  "aud": "vault-broker",                // Vault audience
  "team": "alpha",                      // Team name for policy templating
  "pipeline": "frontend_app",           // Pipeline name
  "run_id": "123",                      // Build number
  "user": "alice.smith",                // Individual developer
  "repo": "monorepo",                   // Repository name
  "target": "//frontend:app",           // Build target
  "iat": 1234567890,                    // Issued at
  "exp": 1234568790                     // Expires
}
```

**Key Points:**
- `sub`: Team-specific entity (bazel-alpha, bazel-beta, etc.)
- `team`: Team identifier for policy templating
- `user`: Individual developer (audit only, doesn't affect entity)
- Same team members share the same `sub` value

### Vault Token Constraints
Child tokens issued by the broker are constrained with:
- **TTL**: 10 minutes maximum lifetime
- **Uses**: Limited to 50 operations
- **Policies**: Restricted to `bazel-team` policy (team-scoped)
- **Metadata**: Includes team, pipeline, user for auditing
- **Non-renewable**: Cannot be extended

### Vault Policies (Team-Based Model)
The `bazel-team` policy uses dynamic templating for team-scoped access:
```hcl
# Team-scoped read access
path "secret/data/bazel/{{identity.entity.aliases.auth_jwt_*.metadata.team}}/*" {
  capabilities = ["read"]
}

# Team-pipeline-scoped secrets  
path "secret/data/bazel/{{identity.entity.aliases.auth_jwt_*.metadata.team}}/{{identity.entity.aliases.auth_jwt_*.metadata.pipeline}}/*" {
  capabilities = ["read"]
}
```

**Policy Templating Examples:**
- JWT with `"team": "alpha"` → Access to `secret/data/bazel/alpha/*`
- JWT with `"team": "beta", "pipeline": "backend_api"` → Access to `secret/data/bazel/beta/backend_api/*`

**Vault Role Configuration:**
```bash
vault write auth/jwt/role/bazel-builds \
  role_type="jwt" \
  user_claim="sub" \
  bound_audiences="vault-broker" \
  bound_issuer="http://localhost:8081" \
  claim_mappings="team=team,pipeline=pipeline,user=user" \
  policies="bazel-team"
```

## Team Configuration

### Team Detection

Teams are detected automatically via:

1. **Git Repository Context** (current implementation):
   ```bash
   # Team alpha developers
   git config user.email alice@company.com    # → team: alpha
   git config user.email bob@company.com      # → team: alpha
   
   # Team beta developers  
   git config user.email dave@company.com     # → team: beta
   git config user.email eve@company.com      # → team: beta
   ```

2. **Environment Override**:
   ```bash
   export TEAM=gamma  # Override team detection
   ```

### Team-to-Secrets Mapping

```bash
# Team Alpha (Frontend) - Entity: bazel-alpha
vault kv put secret/bazel/alpha/shared build_env=staging
vault kv put secret/bazel/alpha/frontend_app api_key=alpha-key

# Team Beta (Backend) - Entity: bazel-beta
vault kv put secret/bazel/beta/shared build_env=production  
vault kv put secret/bazel/beta/backend_api db_url=beta-db

# Team Gamma (Data) - Entity: bazel-gamma
vault kv put secret/bazel/gamma/shared build_env=testing
vault kv put secret/bazel/gamma/ml_pipeline model_path=gamma-models
```

### Team Entity Benefits

- **Logical Workload Grouping**: 1 entity per team (groups identical workloads efficiently)
- **Security**: Teams cannot access other team's secrets or entities
- **Audit**: Clear attribution of access by team and individual  
- **Scalability**: Entity growth = O(teams) not O(developers)

## Production Considerations

### Team-Based Organizations

1. **Use team-specific entity subjects**:
   ```json
   {"sub": "bazel-alpha"}   // Frontend team entity
   {"sub": "bazel-beta"}    // Backend team entity  
   {"sub": "bazel-gamma"}   // Data team entity
   ```

2. **Map identity providers to teams**:
   - Okta group `frontend-team` → JWT `sub: "bazel-alpha"`
   - LDAP group `CN=Backend,OU=Teams` → JWT `sub: "bazel-beta"`
   - Results in 1 entity per team (logically groups identical workloads)

3. **Implement proper key rotation**:
   - Rotate JWT signing keys regularly
   - Update Vault JWT auth configuration accordingly

4. **Monitor entity growth**:
   ```bash
   # Check entity count periodically - should equal number of teams
   vault list identity/entity/id | wc -l
   ```

5. **Team-Based Integration**:
   - Integrate with CI/CD systems (Jenkins, GitHub Actions, etc.)
   - Use Git/workspace metadata for team detection
   - Automate team secret provisioning

### Security Best Practices

- **Secure key management**: Use proper HSMs or key management services
- **Network security**: TLS termination and network policies  
- **Team boundaries**: Ensure teams cannot escalate to other team contexts
- **Audit logging**: Track all JWT exchanges and team context
- **Monitoring**: Alert on unusual entity creation patterns
- **Vault integration**: Proper Vault policies and auth methods

## Troubleshooting

### Environment Variable Issues

**Missing `.env` file:**
```bash
# Copy the template
cp .env.example .env
# Edit with your actual values
vim .env
```

**Wrong Vault token:**
- Check that `VAULT_ROOT_TOKEN` in `.env` matches your Vault root token
- Test Vault connection: `vault status` (with `VAULT_ADDR` set)

**Docker network issues:**
```bash
# Check Docker network connectivity
docker network ls | grep jenkins
# Ensure existing Vault is accessible
docker exec broker curl -f $VAULT_ADDR/v1/sys/health
```

### Broker Service Issues

**Broker won't start:**
- Check that JSON key files exist in the broker directory
- Verify Python dependencies are installed in Docker image
- Ensure port 8081 is available: `lsof -i :8081`
- Check Docker logs: `docker logs broker`

**Authentication failures:**
- Verify `.env` file has correct `BROKER_URL`
- Check team detection: `git config user.email` or set `TEAM` env var
- Test broker health: `curl http://localhost:8081/.well-known/jwks.json`

### Vault Integration Issues
- Verify `VAULT_ADDR` and `VAULT_ROOT_TOKEN` are set in `.env`
- Check that JWT auth backend is enabled: `vault auth list`
- Ensure JWKS URL is accessible from Vault
- Test policy creation: Check Vault logs for policy template errors

### Docker Deployment Issues

**Services won't start:**
```bash
# Check Docker Compose logs
docker-compose logs broker
docker-compose logs vault-setup

# Verify environment file
docker-compose config
```

**Network connectivity:**
```bash
# Test external Vault connection (if using existing Vault)
docker run --rm --network jenkins-vault-poc_default curlimages/curl:latest \
  curl -f http://vault:8200/v1/sys/health

# Check if broker is accessible
curl http://localhost:8081/.well-known/jwks.json
```

### Entity Verification Issues

**Entity sharing not working:**
```bash
# Check verification script output
./verify_entity_sharing.sh

# Look for:
# - Different teams should have different entity IDs
# - Same team members should have identical entity IDs
# - Individual user metadata should be preserved
```

## License

This is a demonstration project for educational purposes.