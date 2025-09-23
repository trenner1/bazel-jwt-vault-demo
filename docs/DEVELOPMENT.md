# Development Guide

This guide provides comprehensive information for developers working on the Enterprise OIDC Vault Demo project.

##  Table of Contents

- [Development Environment Setup](#development-environment-setup)
- [Project Structure](#project-structure)
- [Development Workflow](#development-workflow)
- [Code Standards](#code-standards)
- [Testing Guidelines](#testing-guidelines)
- [Debugging](#debugging)
- [Contributing](#contributing)

## Development Environment Setup

### Prerequisites

- **Python 3.11+**: Latest Python version
- **Docker & Docker Compose**: Container management
- **Git**: Version control
- **Okta Developer Account**: For OIDC testing
- **HashiCorp Vault**: Local or remote instance

### Initial Setup

1. **Clone Repository**:
   ```bash
   git clone https://github.com/trenner1/bazel-jwt-vault-demo.git
   cd bazel-jwt-vault-demo
   ```

2. **Environment Configuration**:
   ```bash
   # Copy environment template
   cp .env.example .env
   
   # Configure Okta settings (required)
   vim .env
   ```

3. **Development Dependencies**:
   ```bash
   # Create virtual environment
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   
   # Install dependencies
   cd broker && pip install -r requirements.txt
   ```

4. **Docker Development Setup**:
   ```bash
   # Build development containers
   docker-compose build
   
   # Start services
   docker-compose up -d
   
   # Configure Vault
   docker-compose run --rm vault-setup
   ```

### IDE Configuration

#### VS Code Setup
```json
// .vscode/settings.json
{
  "python.defaultInterpreterPath": "./.venv/bin/python",
  "python.linting.enabled": true,
  "python.linting.pylintEnabled": true,
  "python.formatting.provider": "black",
  "python.testing.pytestEnabled": true,
  "docker.environment": {
    "COMPOSE_FILE": "docker-compose.yml"
  }
}
```

#### PyCharm Setup
- Configure Python interpreter to use `.venv/bin/python`
- Enable Docker Compose integration
- Set up pytest as test runner
- Configure Black as code formatter

##  Project Structure

```
```
bazel-jwt-vault-demo/
├── broker/                    # OIDC authentication broker
│   ├── app.py                # Main Flask application with PKCE
│   ├── requirements.txt      # Python dependencies
│   └── .env.example         # Environment template
├── client/                   # Legacy client (reference only)
└── docs/                     # Documentation
    ├── ARCHITECTURE.md      # System design
    ├── DEVELOPMENT.md       # This file
    ├── SETUP.md            # Complete setup guide
    └── TESTING.md           # Testing guide
```
├── docs/                      # Documentation
│   ├── ARCHITECTURE.md       # System architecture
│   ├── DEVELOPMENT.md        # This file
│   ├── SETUP.md             # Complete setup guide
│   └── TESTING.md           # Testing procedures
├── scripts/                   # Utility scripts
└── docker-compose.yml        # Development containers
```

### Key Components

#### Broker Application (`broker/app.py`)
- **FastAPI Framework**: Modern async web framework
- **OIDC Integration**: Okta authentication flow
- **Session Management**: Secure session handling
- **Vault Integration**: Token exchange and secret access

#### Vault Configuration (`vault/setup.sh`)
- **OIDC Auth Method**: Configures Vault for Okta
- **Team Policies**: Creates team-specific policies
- **Identity Management**: Sets up groups and entities

#### Test Framework (`tests/`)
- **Integration Tests**: End-to-end OIDC flows
- **Team Isolation**: Verifies access control
- **User Identity**: Tests individual user tracking

##  Development Workflow

### Feature Development

1. **Create Feature Branch**:
   ```bash
   git checkout -b feature/enhance-team-policies
   ```

2. **Develop with Hot Reload**:
   ```bash
   # Start services in development mode
   docker-compose up -d vault
   
   # Run broker with hot reload
   cd broker
   uvicorn app:app --reload --host 0.0.0.0 --port 8081
   ```

3. **Test Changes**:
   ```bash
   # Run integration tests
   ./tests/run-tests.sh
   
   # Test specific functionality
   ./tests/integration/test-okta-auth.sh
   ```

4. **Commit and Push**:
   ```bash
   git add .
   git commit -m "feat: enhance team policy validation"
   git push origin feature/enhance-team-policies
   ```

### Code Review Process

1. **Create Pull Request**: Use GitHub PR template
2. **Automated Checks**: CI/CD runs tests automatically
3. **Code Review**: Team review for quality and security
4. **Integration Testing**: Full system tests in staging
5. **Merge**: Squash merge to main branch

### Release Process

1. **Version Bump**: Update version in appropriate files
2. **Changelog**: Update CHANGELOG.md with changes
3. **Tag Release**: Create git tag with semantic versioning
4. **Deploy**: Automated deployment to staging/production

##  Code Standards

### Python Style Guide

Following PEP 8 with Black formatting:

```python
# Good: Clear imports and docstrings
from typing import Dict, List, Optional
import logging

async def create_team_token(
    user_email: str,
    team_groups: List[str],
    vault_client: hvac.Client
) -> Dict[str, str]:
    """Create team-scoped Vault token for authenticated user.
    
    Args:
        user_email: Authenticated user's email address
        team_groups: List of Okta groups user belongs to
        vault_client: Configured Vault client instance
    
    Returns:
        Dictionary containing token and metadata
        
    Raises:
        VaultError: If token creation fails
    """
    logger.info(f"Creating team token for {user_email}")
    # Implementation here
```

### FastAPI Patterns

```python
# Good: Proper dependency injection and error handling
from fastapi import FastAPI, Depends, HTTPException
from pydantic import BaseModel

class TokenRequest(BaseModel):
    team: str
    duration: Optional[int] = 3600

@app.post("/token")
async def create_token(
    request: TokenRequest,
    user_session: dict = Depends(get_current_user)
) -> TokenResponse:
    try:
        token = await create_team_token(user_session, request)
        return TokenResponse(token=token)
    except VaultError as e:
        raise HTTPException(status_code=500, detail=str(e))
```

### Error Handling

```python
# Good: Structured error handling with logging
import logging
from typing import Optional

logger = logging.getLogger(__name__)

class VaultAuthError(Exception):
    """Vault authentication specific errors."""
    pass

async def authenticate_with_vault(oidc_token: str) -> Optional[str]:
    try:
        response = await vault_client.auth.oidc.submit_challenge(
            token=oidc_token
        )
        logger.info("Vault authentication successful")
        return response["auth"]["client_token"]
    except hvac.exceptions.VaultError as e:
        logger.error(f"Vault authentication failed: {e}")
        raise VaultAuthError(f"Authentication failed: {e}")
    except Exception as e:
        logger.error(f"Unexpected error during authentication: {e}")
        raise
```

### Configuration Management

```python
# Good: Structured configuration with validation
from pydantic import BaseSettings, validator
from typing import Optional

class Settings(BaseSettings):
    # Okta Configuration
    okta_domain: str
    okta_client_id: str
    okta_client_secret: str
    okta_redirect_uri: str = "http://localhost:8081/auth/callback"
    
    # Vault Configuration
    vault_addr: str = "http://vault:8200"
    vault_token: Optional[str] = None
    
    # Application Configuration
    session_secret_key: str = "dev-secret-change-in-production"
    log_level: str = "INFO"
    
    @validator("okta_domain")
    def validate_okta_domain(cls, v):
        if not v.endswith(".okta.com"):
            raise ValueError("Okta domain must end with .okta.com")
        return v
    
    class Config:
        env_file = ".env"

settings = Settings()
```

##  Testing Guidelines

### Unit Testing

```python
# tests/unit/test_token_creation.py
import pytest
from unittest.mock import AsyncMock, patch
from broker.app import create_team_token

@pytest.mark.asyncio
async def test_create_team_token_success():
    # Given
    user_email = "alice@company.com"
    team_groups = ["mobile-developers"]
    mock_vault_client = AsyncMock()
    mock_vault_client.auth.oidc.login.return_value = {
        "auth": {"client_token": "hvs.EXAMPLE-TOKEN"}
    }
    
    # When
    result = await create_team_token(user_email, team_groups, mock_vault_client)
    
    # Then
    assert result["token"].startswith("hvs.")
    assert result["team"] == "mobile-team"
    mock_vault_client.auth.oidc.login.assert_called_once()

@pytest.mark.asyncio
async def test_create_team_token_vault_error():
    # Given
    user_email = "alice@company.com"
    team_groups = ["mobile-developers"]
    mock_vault_client = AsyncMock()
    mock_vault_client.auth.oidc.login.side_effect = Exception("Vault error")
    
    # When & Then
    with pytest.raises(VaultAuthError):
        await create_team_token(user_email, team_groups, mock_vault_client)
```

### Integration Testing

```bash
# tests/integration/test-okta-auth.sh
#!/bin/bash
set -e

# Test OIDC authentication flow
echo "Testing Okta OIDC authentication..."

# Check broker health
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/health)
if [ "$response" != "200" ]; then
    echo " Broker health check failed"
    exit 1
fi

echo " Broker health check passed"

# Test authentication endpoint
auth_url=$(curl -s http://localhost:8081/auth/url | jq -r '.auth_url')
if [[ "$auth_url" != *"okta.com"* ]]; then
    echo " Okta auth URL not properly configured"
    exit 1
fi

echo " Okta authentication URL configured correctly"
```

### Test Data Management

```python
# tests/conftest.py
import pytest
from typing import Generator
import asyncio

@pytest.fixture
def vault_test_client():
    """Provide isolated Vault client for testing."""
    client = hvac.Client(url="http://localhost:8200")
    client.token = "test-token"
    yield client
    # Cleanup test data
    client.secrets.kv.v2.delete_metadata_and_all_versions(
        path="test-secrets"
    )

@pytest.fixture
def sample_user_session():
    """Provide sample user session for testing."""
    return {
        "user_email": "test@company.com",
        "groups": ["mobile-developers"],
        "expires_at": "2024-12-31T23:59:59Z"
    }
```

## � CLI Tools Development

### Tool Architecture

The CLI tools follow a layered architecture:

```
┌─────────────────────────────────────────────────────────┐
│                User Interface Layer                     │
├─────────────────────────────────────────────────────────┤
│ - Argument parsing                                      │
│ - User feedback (emojis, colors)                       │
│ - Error messaging                                       │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│              Authentication Layer                       │
├─────────────────────────────────────────────────────────┤
│ - PKCE parameter generation                             │
│ - Browser automation                                    │
│ - Session exchange logic                                │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│               HTTP Client Layer                         │
├─────────────────────────────────────────────────────────┤
│ - curl wrapper (bazel-auth-simple)                     │
│ - requests library (bazel-auth)                        │
│ - Error handling and retries                           │
└─────────────────────────────────────────────────────────┘
```

### Adding New CLI Tools

1. **Create Tool Structure**:
   ```bash
   # Create new tool file
   touch tools/my-new-tool
   chmod +x tools/my-new-tool
   ```

2. **Follow Naming Convention**:
   ```bash
   # Pattern: bazel-[purpose][-modifier]
   tools/bazel-auth-simple     # Simple authentication
   tools/bazel-auth            # Full authentication  
   tools/bazel-build           # Build wrapper
   tools/bazel-test            # Test wrapper (future)
   ```

3. **Implement Standard Interface**:
   ```bash
   #!/usr/bin/env bash
   # tools/my-new-tool
   
   # Standard help message
   if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
       echo "Usage: $0 [options]"
       echo "Description: Brief description of tool"
       exit 0
   fi
   
   # Standard error handling
   set -euo pipefail
   
   # Tool implementation...
   ```

### CLI Testing

```bash
# Test all CLI tools
./tests/integration/test-cli-tools.sh

# Test specific tool
./tests/integration/test-bazel-auth-simple.sh

# Manual testing
./tools/bazel-auth-simple --no-browser  # Test URL generation
./tools/bazel-auth-simple --help        # Test help output
```

## �🐛 Debugging

### Application Debugging

1. **Enable Debug Logging**:
   ```python
   # broker/app.py
   import logging
   logging.basicConfig(level=logging.DEBUG)
   logger = logging.getLogger(__name__)
   
   @app.middleware("http")
   async def log_requests(request: Request, call_next):
       logger.debug(f"Request: {request.method} {request.url}")
       response = await call_next(request)
       logger.debug(f"Response: {response.status_code}")
       return response
   ```

2. **Docker Container Debugging**:
   ```bash
   # Access running container
   docker exec -it broker /bin/bash
   
   # View container logs
   docker logs -f broker
   
   # Check container environment
   docker exec broker env | grep OKTA
   ```

### Vault Debugging

```bash
# Enable Vault debug logging
export VAULT_LOG_LEVEL=debug

# Check Vault status
vault status

# Verify OIDC configuration
vault read auth/oidc/config

# Test OIDC role
vault read auth/oidc/role/team-oidc

# Check audit logs
vault audit list
tail -f /vault/logs/audit.log
```

### Network Debugging

```bash
# Test network connectivity
docker network ls
docker network inspect bazel-jwt-vault-demo_default

# Test service communication
docker exec broker curl -f http://vault:8200/v1/sys/health

# Check port accessibility
netstat -tulpn | grep :8081
lsof -i :8081
```

### Common Issues and Solutions

#### OIDC Authentication Failures
```bash
# Check Okta configuration
curl -s "https://${OKTA_DOMAIN}/.well-known/openid_configuration"

# Verify client credentials
echo "Client ID: ${OKTA_CLIENT_ID}"
echo "Redirect URI: ${OKTA_REDIRECT_URI}"

# Test token exchange manually
curl -X POST "https://${OKTA_DOMAIN}/oauth2/default/v1/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code&code=${AUTH_CODE}&client_id=${OKTA_CLIENT_ID}&client_secret=${OKTA_CLIENT_SECRET}&redirect_uri=${OKTA_REDIRECT_URI}"
```

#### Vault Connection Issues
```bash
# Test Vault connectivity
curl -f ${VAULT_ADDR}/v1/sys/health

# Check authentication
vault auth -method=userpass username=test

# Verify policies
vault policy list
vault policy read team-policy
```

#### Session Management Issues
```python
# Debug session data
@app.get("/debug/session")
async def debug_session(request: Request):
    session_data = request.session
    return {
        "session_id": session_data.get("session_id"),
        "user_email": session_data.get("user_email"),
        "expires_at": session_data.get("expires_at")
    }
```

##  Contributing

### Pull Request Guidelines

1. **Branch Naming**: Use descriptive branch names:
   - `feature/add-user-management`
   - `fix/session-timeout-bug`
   - `docs/update-api-documentation`

2. **Commit Messages**: Follow conventional commits:
   ```
   feat: add team-based secret isolation
   fix: resolve session timeout issue
   docs: update API documentation
   test: add integration tests for OIDC flow
   ```

3. **Code Quality Checklist**:
   - [ ] Code follows style guidelines
   - [ ] Tests added for new functionality
   - [ ] Documentation updated
   - [ ] Security considerations reviewed
   - [ ] Performance impact assessed

### Security Review Process

1. **Authentication Changes**: Extra review for auth-related code
2. **Vault Integration**: Verify policy templates and permissions
3. **Session Management**: Review session handling and storage
4. **Input Validation**: Ensure proper validation and sanitization

### Documentation Requirements

- **Code Comments**: Complex logic should be commented
- **API Documentation**: Update OpenAPI specs for API changes
- **User Documentation**: Update README and guides as needed
- **Architecture Documentation**: Update for significant changes

##  Additional Resources

### Development Tools
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Pydantic Documentation](https://pydantic-docs.helpmanual.io/)
- [HVAC (Vault Client) Documentation](https://hvac.readthedocs.io/)
- [Okta Developer Documentation](https://developer.okta.com/)

### Testing Tools
- [pytest Documentation](https://docs.pytest.org/)
- [pytest-asyncio](https://pytest-asyncio.readthedocs.io/)
- [httpx Testing Client](https://www.python-httpx.org/)

### Deployment Tools
- [Docker Documentation](https://docs.docker.com/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Kubernetes Documentation](https://kubernetes.io/docs/) (for production)

This development guide should help you get started with contributing to the Enterprise OIDC Vault Demo project. For additional questions, please check the existing documentation or open an issue on GitHub.