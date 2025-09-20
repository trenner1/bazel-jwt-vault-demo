# Bazel JWT Vault Demo - Team-Based Edition

A demonstration of **team-based JWT authentication** for Bazel builds with HashiCorp Vault, featuring logical license grouping and transparent authentication based on the [Jenkins Vault POC](https://github.com/trenner1/jenkins-vault-poc) pattern.

## What This POC Proves

- **Zero Entity Churning**: Same entity/alias reused across team member builds
- **Logical License Grouping**: Entity count scales with teams, not developers
- **Transparent Authentication**: Developers never handle tokens directly
- **Team-Based Access Control**: Natural isolation boundaries align with org structure
- **Scalable**: Supports large monorepos with multiple development teams

**Verified**: Real JWT authentication with team-based entity ID tracking - **no churning within teams**.

## Architecture Overview

### Team-Based Entity Model

```
Team Alpha (Frontend)     →  Entity: team-alpha  →  Secrets: secret/bazel/team-alpha/*
├── alice@company.com          
├── bob@company.com            
└── carol@company.com         

Team Beta (Backend)       →  Entity: team-beta   →  Secrets: secret/bazel/team-beta/*
├── dave@company.com           
├── eve@company.com            
└── frank@company.com          

Team Gamma (ML/Data)      →  Entity: team-gamma  →  Secrets: secret/bazel/team-gamma/*
├── grace@company.com          
└── henry@company.com          
```

**Benefits:**
- **No Churning**: Same entity reused by all team members
- **Licensing Efficient**: Entity count = number of teams (not developers)
- **Secure**: Team-scoped access via dynamic policy templating
- **Transparent**: Build tools handle authentication automatically

```
┌─────────────┐    JWT         ┌─────────────┐   Vault Token    ┌─────────────┐
│ Bazel Build │ ──────────────> │ JWT Broker  │ ───────────────> │    Vault    │
│ (Team-Alpha)│  (team context) │             │  (team-scoped)   │ Team Secrets│
└─────────────┘                 └─────────────┘                  └─────────────┘
      ↑                                                                   
  Completely                                                              
  Transparent                                                             
  to Developer                                                            
```

## Project Structure

```
bazel-jwt-vault-demo/
├── broker/                    # FastAPI JWT broker service
│   ├── app.py                 # Main broker application (team-based)
│   ├── start.py               # Startup script
│   ├── gen_keys.py            # RSA key generation utility
│   ├── requirements.txt       # Python dependencies
│   ├── requirements.lock      # Locked dependency versions (for Bazel)
│   ├── jwks.json              # Public keys (JWKS format)
│   ├── signer_keys.json       # Private keys (development only)
│   └── BUILD                  # Bazel build configuration
├── client/                    # Demo client simulation
│   ├── build_sim.sh           # Team-based build workflow demo
│   └── BUILD                  # Bazel build configuration
├── vault/                     # Vault configuration
│   ├── setup.sh               # Vault setup with team policies
│   ├── bazel-team-policy.hcl  # Team-scoped policy template
│   └── BUILD                  # Bazel build configuration
├── scripts/                   # Transparent authentication tools
│   ├── bazel-auth.sh          # Transparent team-based auth
│   └── verify-team-entities.sh # Entity churning verification
├── .bazelteam                 # Team configuration for this repo
├── MODULE.bazel               # Bazel module configuration
└── BUILD                      # Top-level Bazel targets
```

## Prerequisites

- **Bazel** 8.4.1+ (installed via Homebrew)
- **Python** 3.11+ with pip
- **HashiCorp Vault** (for production testing)
- **curl** and **jq** (for testing)

## Quick Start

### 1. Install Dependencies

```bash
# Install Bazel (if not already installed)
brew install bazel

# The Python virtual environment is automatically configured
```

### 2. Start the JWT Broker

```bash
# Option 1: Using the startup script
/path/to/your/venv/bin/python broker/start.py

# Option 2: Using Bazel
bazel run //broker:broker

# The broker will start on http://localhost:8081
```

### 3. Test the Broker

```bash
# Test the JWKS endpoint
curl -s http://localhost:8081/.well-known/jwks.json | jq .

# Test JWT signing (demo endpoint)
curl -s http://localhost:8081/demo/sign \
  -H 'content-type: application/json' \
  -d '{"sub":"test","repo":"demo","target":"//test:demo"}' | jq .
```

### 4. Configure Vault (Optional)

If you have Vault running:

```bash
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="your-vault-token"

# Run the Vault setup script
./vault/setup.sh

# Or using Bazel
bazel run //vault:vault_setup
```

### 5. Run Team-Based Authentication (New!)

```bash
# Transparent authentication - developers never see tokens!
./scripts/bazel-auth.sh "//frontend:app"

# This automatically:
# 1. Detects team from .bazelteam file
# 2. Gets JWT with team context
# 3. Exchanges for team-scoped Vault token
# 4. Sets environment for build tools
```

### 6. Verify Team Entity Model

```bash
# Verify no entity churning within teams
./scripts/verify-team-entities.sh

# This proves the licensing-efficient pattern
```

## Bazel Build Targets

This project supports building with Bazel:

```bash
# List all available targets
bazel query //...

# Build the broker
bazel build //broker:broker

# Build key generation utility
bazel build //broker:gen_keys

# Run targets directly
bazel run //broker:broker      # Start the broker service
bazel run //broker:gen_keys    # Generate new RSA keys
bazel run //client:build_sim   # Run client demo
bazel run //vault:vault_setup  # Configure Vault
```

## Key Management

### Generate New Keys

```bash
# Using Python directly
cd broker && python gen_keys.py

# Using Bazel
bazel run //broker:gen_keys
```

This generates:
- `broker/jwks.json` - Public keys in JWKS format (used by Vault)
- `broker/signer_keys.json` - Private keys (development only)

### Key Security Notes

- **Development**: Private keys are stored in `signer_keys.json` for demo purposes
- **Production**: Use proper key management (HSMs, Vault Transit, etc.)
- **Rotation**: Regenerate keys periodically and update Vault configuration

## API Endpoints

### JWT Broker (`http://localhost:8081`)

#### `GET /.well-known/jwks.json`
Returns the public key set for JWT verification.

#### `POST /demo/sign`
Development endpoint that signs demo JWTs.

**Request:**
```json
{
  "team": "team-alpha",
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
    "sub": "team-alpha",
    "team": "team-alpha",
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
    "team": "team-alpha",
    "pipeline": "frontend_app",
    "user": "alice@company.com",
    "run_id": "build-123",
    "groups": "bazel-dev,team-alpha",
    "issued_by": "broker"
  }
}
```

## Environment Variables

### Broker Configuration
- `VAULT_ADDR` - Vault server address (default: `http://127.0.0.1:8200`)
- `VAULT_TOKEN` - Broker's Vault token (development only)
- `ISSUER` - JWT issuer (default: `http://localhost:8080`)
- `AUDIENCE` - JWT audience (default: `vault-broker`)
- `KEYSET_PATH` - Path to JWKS file (default: `jwks.json`)
- `SIGNER_KEYS_PATH` - Path to private keys (default: `signer_keys.json`)
- `VAULT_JWT_ROLE` - Vault JWT role name (default: `bazel-builds`)

### Client Configuration
- `BROKER` - Broker service URL (default: `http://127.0.0.1:8080`)
- `VAULT_ADDR` - Vault server address (default: `http://127.0.0.1:8200`)

## Security Model

### JWT Claims (Team-Based)
Required claims in build JWTs:
- `iss` - Issuer (must match broker configuration)
- `aud` - Audience (must match broker configuration)  
- `sub` - **Team identifier** (e.g., "team-alpha", "team-beta")
- `exp` - Expiration time
- `iat` - Issued at time
- `repo` - Repository name
- `target` - Build target
- `team` - Team name (for policy templating)
- `pipeline` - Pipeline identifier (derived from target)
- `user` - Individual developer (for audit only)
- `groups` - User/build groups
- `run_id` - Unique run identifier

### Vault Token Constraints
Child tokens issued by the broker are constrained with:
- **TTL**: 10 minutes maximum lifetime
- **Uses**: Limited to 50 operations
- **Policies**: Restricted to `bazel-team` policy (team-scoped)
- **Metadata**: Includes team, pipeline, user for auditing
- **Non-renewable**: Cannot be extended

### Vault Policies (Team-Scoped)
The `bazel-team` policy uses dynamic templating:
```hcl
# Team-scoped access
path "secret/data/bazel/{{identity.entity.aliases.auth_jwt_*.metadata.team}}/*" {
  capabilities = ["read"]
}

# Pipeline-specific secrets  
path "secret/data/bazel/{{identity.entity.aliases.auth_jwt_*.metadata.team}}/{{identity.entity.aliases.auth_jwt_*.metadata.pipeline}}/*" {
  capabilities = ["read"]
}
```

**Example**: Team "team-alpha" building "frontend_app" gets access to:
- `secret/data/bazel/team-alpha/*` (team-wide secrets)
- `secret/data/bazel/team-alpha/frontend_app/*` (pipeline-specific)

## Team Configuration

### Setting Up Teams

1. **Create `.bazelteam` file** in your repository root:
   ```
   team-alpha
   ```

2. **Team Detection Logic** (in practice, this would integrate with):
   - **LDAP/Active Directory**: Map user groups to teams
   - **Okta/SSO**: Use group memberships 
   - **Git Repository**: Team ownership files
   - **CI System**: Environment variables

3. **Team-to-Secrets Mapping**:
   ```bash
   # Team Alpha (Frontend)
   vault kv put secret/bazel/team-alpha/shared build_env=staging
   vault kv put secret/bazel/team-alpha/frontend_app api_key=alpha-key
   
   # Team Beta (Backend)  
   vault kv put secret/bazel/team-beta/shared build_env=production
   vault kv put secret/bazel/team-beta/backend_api db_url=beta-db
   ```

### Team Isolation Benefits

- **Licensing**: 1 entity per team (not per developer)
- **Security**: Teams cannot access other team's secrets
- **Audit**: Clear attribution of access by team and individual
- **Scalability**: Entity growth = O(teams) not O(developers)

## Production Considerations

### Team-Based Organizations

1. **Use team-specific `sub` claims**:
   ```json
   {"sub": "team-alpha"}  // Frontend team
   {"sub": "team-beta"}   // Backend team  
   {"sub": "team-gamma"}  // Data team
   ```

2. **Map identity providers to teams**:
   - Okta group `frontend-team` → JWT `sub: "team-alpha"`
   - LDAP group `CN=Backend,OU=Teams` → JWT `sub: "team-beta"`
   - Results in 1 entity per team (logical license grouping)

3. **Implement proper key rotation**:
   - Rotate JWT signing keys regularly
   - Update Vault JWT auth configuration accordingly

4. **Monitor entity growth**:
   ```bash
   # Check entity count periodically
   vault list identity/entity/id | wc -l
   ```

5. **Team-Based Integration**:
   - Integrate with CI/CD systems (Jenkins, GitHub Actions, etc.)
   - Use workspace/repository metadata for team detection
   - Automate team secret provisioning

### Security Best Practices

- **Secure key management**: Use proper HSMs or key management services
- **Network security**: TLS termination and network policies  
- **Team boundaries**: Ensure teams cannot escalate to other team contexts
- **Audit logging**: Track all JWT exchanges and team context
- **Monitoring**: Alert on unusual entity creation patterns
- **Vault integration**: Proper Vault policies and auth methods

## Troubleshooting

### Broker Won't Start
- Check that JSON key files exist in the broker directory
- Verify Python dependencies are installed
- Ensure port 8081 is available

### Bazel Build Issues
- Run `bazel clean` if builds fail
- Check that `requirements.lock` is up to date
- Verify Python toolchain is configured correctly

### Vault Integration Issues
- Verify `VAULT_ADDR` and `VAULT_TOKEN` are set
- Check that JWT auth backend is enabled
- Ensure JWKS URL is accessible from Vault

## License

This is a demonstration project for educational purposes.