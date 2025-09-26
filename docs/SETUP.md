#  OIDC Enterprise Setup Guide

This guide provides comprehensive instructions for setting up the Enterprise OIDC authentication system with HashiCorp Vault and Okta integration.

##  Table of Contents

- [Quick Start](#quick-start)
- [Okta Configuration](#okta-configuration)
- [Environment Setup](#environment-setup)
- [Docker Deployment](#docker-deployment)
- [CLI Tools Setup](#cli-tools-setup)
- [Team Configuration](#team-configuration)
- [Testing & Validation](#testing--validation)
- [Advanced Deployment](#advanced-deployment)
- [Troubleshooting](#troubleshooting)

##  Quick Start

For immediate setup with default configuration:

```bash
# Clone and setup
git clone https://github.com/trenner1/bazel-jwt-vault-demo.git
cd bazel-jwt-vault-demo

# Generate JWT signing keys
./scripts/generate-jwt-keys.sh

# Configure environment
cp .env.example .env
# Edit .env with your Okta details

# Start services
docker-compose up -d

# Test CLI tool
./tools/bazel-auth-simple
```

##  Okta Configuration

### Prerequisites

- Okta Developer Account (free at https://developer.okta.com)
- Admin access to create applications and groups
- Understanding of OIDC authentication flows

### Step 1: Create Okta Application

1. **Login to Okta Admin Console**
   - Navigate to Applications → Applications
   - Click "Create App Integration"

2. **Configure Application**
   - Sign-in method: **OIDC - OpenID Connect**
   - Application type: **Web Application**
   - Application name: `Bazel Vault Demo`

3. **Grant Types & Redirects**
   ```
   Grant types allowed:
    Authorization Code
    Refresh Token
   
   Sign-in redirect URIs:
   http://localhost:5000/oidc/callback
   
   Sign-out redirect URIs:
   http://localhost:5000/
   
   Trusted Origins:
   http://localhost:5000
   ```

4. **PKCE Configuration**
   - **Proof Key for Code Exchange (PKCE)**:  **Required**
   - **Client authentication**: Public client (PKCE only)

### Step 2: Create Team Groups

Create Okta groups for team-based access control:

```bash
# In Okta Admin Console → Directory → Groups
Create Groups:
├── mobile-developers      # Access to mobile team secrets
├── backend-developers     # Access to backend team secrets  
├── frontend-developers    # Access to frontend team secrets
└── devops-team           # Cross-functional access
```

### Step 3: Assign Users to Groups

Add team members to appropriate groups:
- Users inherit team permissions automatically
- Multiple group membership supported
- Groups map directly to Vault policies

### Step 4: Get Application Credentials

From your Okta application settings:
```bash
# Copy these values for environment configuration
OKTA_DOMAIN=your-domain.okta.com
OKTA_CLIENT_ID=0oa1a2b3c4d5e6f7g8h9
```

##  Environment Setup

### Broker Configuration

Create and configure `broker/.env`:

```bash
# Okta OIDC Configuration
OKTA_DOMAIN=your-domain.okta.com
OKTA_CLIENT_ID=0oa1a2b3c4d5e6f7g8h9
OKTA_CLIENT_SECRET=your-client-secret-here
OKTA_REDIRECT_URI=http://localhost:8081/auth/callback

# Vault Configuration  
VAULT_ADDR=http://vault:8200
VAULT_ROOT_TOKEN=your-vault-root-token

# Development Settings (optional)
DEBUG=false
LOG_LEVEL=INFO
```

### Environment Variables

Essential environment variables for deployment:

| Variable | Description | Example |
|----------|-------------|---------|
| `OKTA_DOMAIN` | Your Okta domain | `dev-123456.okta.com` |
| `OKTA_CLIENT_ID` | Application client ID | `0oa1a2b3c4d5e6f7g8h9` |
| `OKTA_CLIENT_SECRET` | Application client secret | `your-secret-here` |
| `OKTA_REDIRECT_URI` | Callback URL | `http://localhost:8081/auth/callback` |
| `VAULT_ADDR` | Vault server address | `http://vault:8200` |
| `VAULT_ROOT_TOKEN` | Vault root token | `hvs.ABC123...` |

### JWT Key Pair Generation

The broker requires RSA key pairs for JWT token signing and verification:

```bash
# Generate RSA key pair for JWT signing
./scripts/generate-jwt-keys.sh
```

This creates:
- `broker/jwt_signing_key` - Private key for token signing (keep secure!)
- `broker/jwt_signing_key.pub` - Public key for token verification  
- `broker/jwt_public_key.pem` - Public key in PEM format

**Important Security Notes:**
- **Never commit private keys to version control**
- Private key is used by broker to sign JWT tokens
- Public key is used by Vault to verify JWT signatures
- For advanced deployment, use proper key management solutions

#### Regenerating JWT Keys

If you need to regenerate the JWT keys (for security rotation or if keys are compromised):

```bash
# 1. Generate new key pair
./scripts/generate-jwt-keys.sh

# 2. Rebuild broker container with new keys
docker-compose build broker
docker-compose up -d broker

# 3. Update Vault with new public key
./vault/setup.sh

# 4. Verify the system is working
./tools/bazel-auth-simple --help
```

**Key Rotation Impact:**
- All existing JWT tokens become invalid immediately
- Users will need to re-authenticate after key rotation
- This is a disruptive operation - plan accordingly

##  Docker Deployment

### Development Deployment

```bash
# Start complete environment
docker-compose up -d

# Verify services
docker ps | grep -E "(broker|vault)"

# Check logs
docker-compose logs broker
docker-compose logs vault-setup
```

### Service Architecture

```yaml
# docker-compose.yml structure
services:
  vault:          # HashiCorp Vault server
  vault-setup:    # OIDC configuration automation  
  broker:         # OIDC authentication broker
```

### Port Configuration

| Service | Port | Purpose |
|---------|------|---------|
| Broker | 8081 | OIDC authentication & callback |
| Vault | 8200 | Secret management & token validation |

## CLI Tools Setup

The demo includes multiple CLI tools for different use cases:

### bazel-auth-simple (Recommended)

Zero-dependency CLI tool for PKCE authentication:

```bash
# Make executable (if needed)
chmod +x tools/bazel-auth-simple

# Start authentication flow
./tools/bazel-auth-simple

# Help and options
./tools/bazel-auth-simple --help
./tools/bazel-auth-simple --no-browser  # For testing
```

### bazel-auth (Advanced)

Python-based CLI with additional features:

```bash
# Install dependencies
pip install -r broker/requirements.txt

# Use tool
./tools/bazel-auth --export  # Export token to environment
./tools/bazel-auth --info    # Show token information
```

### bazel-build (Wrapper)

Bazel wrapper that handles authentication automatically:

```bash
# Use like normal bazel but with automatic auth
./tools/bazel-build build //...
./tools/bazel-build test //tests/...
```

##  Team Configuration

### Automatic Team Mapping

Teams are automatically configured based on Okta groups:

```python
# Automatic mapping in broker/app.py
TEAM_MAPPING = {
    'mobile-developers': 'mobile-team',
    'backend-developers': 'backend-team', 
    'frontend-developers': 'frontend-team',
    'devops-team': 'devops-team'
}
```

### Vault Policy Creation

Policies are automatically created by `vault-setup` service:

```hcl
# Example: mobile-team policy
path "kv/data/mobile/*" {
  capabilities = ["read", "list"]
}

path "kv/data/shared/*" {  
  capabilities = ["read", "list"]
}
```

### Secret Organization

Organize secrets by team in Vault:

```
vault/
├── kv/
│   ├── mobile/           # Mobile team secrets
│   │   ├── api-keys
│   │   └── certificates
│   ├── backend/          # Backend team secrets  
│   │   ├── database-creds
│   │   └── service-tokens
│   ├── frontend/         # Frontend team secrets
│   │   ├── api-endpoints
│   │   └── cdn-configs
│   └── shared/           # Cross-team secrets
│       ├── common-config
│       └── environments
```

##  Testing & Validation

### Quick Validation

```bash
# Run test suite
./tests/run-tests.sh

# Test specific components
./tests/integration/test-okta-auth.sh     # OIDC authentication
./tests/integration/test-cli-tools.sh     # CLI tools validation
./tests/integration/test-team-isolation.sh # Team access control
```

### Manual Testing

1. **CLI Authentication**:
   ```bash
   ./tools/bazel-auth-simple
   # Complete Okta login in browser
   # Copy session_id from enhanced callback page
   ```

2. **Token Exchange**:
   ```bash
   curl -X POST http://localhost:5000/child-token \
     -H "Content-Type: application/json" \
     -d '{"session_id": "YOUR_SESSION_ID"}'
   ```

3. **Vault Access**:
   ```bash
   export VAULT_TOKEN="your-token-here"
   vault kv get kv/mobile/api-keys
   ```

### PKCE Flow Validation

Verify PKCE parameters are properly configured:

```bash
# Test PKCE flow initiation
curl -X POST http://localhost:5000/cli/start

# Check for required parameters:
# - code_challenge
# - code_challenge_method=S256
# - state (CSRF protection)
```

##  Advanced Deployment

### Security Considerations

1. **HTTPS Required**: All advanced deployments should use HTTPS
2. **Secure Secrets**: Use proper secret management for environment variables
3. **Network Security**: Implement proper network segmentation
4. **Monitoring**: Add comprehensive logging and monitoring

### Advanced Environment Variables

```bash
# Advanced deployment configuration
OKTA_DOMAIN=company.okta.com
OKTA_CLIENT_ID=advanced-client-id
OKTA_CLIENT_SECRET=advanced-client-secret
OKTA_REDIRECT_URI=https://vault-broker.company.com/auth/callback
VAULT_ADDR=https://vault.company.com:8200
VAULT_ROOT_TOKEN=advanced-vault-token
HTTPS_ONLY=true
```

### Scaling Considerations

- **Load Balancing**: Broker service is stateless and can be horizontally scaled
- **Session Storage**: Consider Redis for session storage in multi-instance deployments
- **Vault HA**: Use Vault High Availability configuration for advanced setups
- **Monitoring**: Implement health checks and metrics collection

##  Troubleshooting

### Common Issues

#### 1. OIDC Authentication Fails

```bash
# Check Okta configuration
curl -s http://localhost:5000/health | jq '.auth_method'

# Verify environment variables
docker exec broker env | grep OKTA
```

#### 2. CLI Tools Not Working

```bash
# Check tool permissions
ls -la tools/bazel-auth-simple

# Test broker connectivity
curl -X POST http://localhost:5000/cli/start
```

#### 3. JWT Authentication Failures

If authentication fails with JWT-related errors:

```bash
# Check if JWT keys exist
ls -la broker/jwt_signing_key*

# Verify keys in container match host
docker exec bazel-broker ls -la /app/jwt_signing_key*

# If keys are missing or mismatched, regenerate and update:
./scripts/generate-jwt-keys.sh
docker-compose build broker
docker-compose up -d broker
./vault/setup.sh
```

**Common JWT errors:**
- `signature verification failed` → Key mismatch between broker and Vault
- `issuer does not match` → Check issuer configuration in JWT and Vault
- `token expired` → Normal - tokens expire after 2 hours

#### 4. Team Access Issues

```bash
# Check Okta groups
# User must be in correct Okta groups
# Groups must match broker/app.py TEAM_MAPPING

# Test token metadata
vault auth -method=token token=YOUR_TOKEN
vault token lookup -self
```

#### 5. Vault Connection Issues

```bash
# Check Vault health
curl http://localhost:8200/v1/sys/health

# Check OIDC mount
vault auth list | grep oidc
```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# In broker/.env
DEBUG=true
LOG_LEVEL=DEBUG

# Restart broker
docker-compose restart broker

# Check detailed logs
docker-compose logs -f broker
```

### Support Resources

- **Architecture Documentation**: `docs/ARCHITECTURE.md`
- **Development Guide**: `docs/DEVELOPMENT.md`
- **Testing Guide**: `docs/TESTING.md`
- **GitHub Issues**: Report issues with detailed logs and configuration

##  Additional Resources

### Documentation

- [OIDC Specification](https://openid.net/connect/)
- [PKCE RFC 7636](https://tools.ietf.org/html/rfc7636)
- [HashiCorp Vault OIDC](https://www.vaultproject.io/docs/auth/oidc)
- [Okta Developer Documentation](https://developer.okta.com/docs/)

### Best Practices

1. **Security**: Always use PKCE for public clients
2. **Team Management**: Keep Okta groups synchronized with team structure
3. **Secret Organization**: Use consistent naming conventions for secret paths
4. **Monitoring**: Implement comprehensive audit logging
5. **Testing**: Regularly test authentication flows and team isolation

---

##  Success!

You now have a fully configured Enterprise OIDC authentication system with:

-  **Secure PKCE Authentication** with Okta integration
-  **Zero-dependency CLI Tools** for developer productivity  
-  **Team-based Access Control** via Okta groups
-  **Enhanced User Experience** with auto-copy callback page
-  **Demo-ready Architecture** with proper security controls

For ongoing maintenance and updates, refer to the comprehensive documentation in the `docs/` directory.