# 🧪 Testing Guide

This comprehensive testing guide covers all aspects of testing the Enterprise OIDC Vault Demo, from unit tests to end-to-end integration testing.

## 📋 Table of Contents

- [Testing Philosophy](#testing-philosophy)
- [Test Suite Overview](#test-suite-overview)
- [Running Tests](#running-tests)
- [Integration Tests](#integration-tests)
- [Unit Testing](#unit-testing)
- [Performance Testing](#performance-testing)
- [Security Testing](#security-testing)
- [Troubleshooting Tests](#troubleshooting-tests)

## 🎯 Testing Philosophy

Our testing strategy follows the testing pyramid principle:

```
         /\
        /  \
       /    \
      / E2E  \     ← Few, high-value integration tests
     /_______ \
    /          \
   / Integration \   ← Key workflow testing
  /______________\
 /                \
/ Unit Tests      \  ← Many, fast, focused tests
\__________________/
```

### Testing Principles

1. **Comprehensive Coverage**: Test all critical authentication and authorization flows
2. **Real Environment**: Integration tests use actual Okta and Vault instances
3. **Team Isolation**: Verify complete separation between team access
4. **Security First**: Validate all security controls and edge cases
5. **Performance Awareness**: Monitor performance characteristics under load

## 📊 Test Suite Overview

### Test Categories

| Test Type | Location | Purpose | Frequency |
|-----------|----------|---------|-----------|
| **Integration** | `tests/integration/` | End-to-end OIDC flows | Manual/CI |
| **Unit** | `tests/unit/` | Component testing | Pre-commit |
| **Security** | `tests/security/` | Security validation | Weekly |
| **Performance** | `tests/performance/` | Load testing | Release |

### Test Files

```
tests/
├── run-tests.sh                      # Interactive test runner
├── integration/                      # Integration test suites
│   ├── test-okta-auth.sh            # OIDC PKCE authentication flow
│   ├── test-cli-tools.sh            # CLI tools validation
│   ├── test-team-isolation.sh       # Team access control
│   ├── test-user-identity.sh        # User identity tracking
│   └── test-full-workflow.sh        # Comprehensive workflow
├── unit/                             # Unit tests (Python)
│   ├── test_token_management.py     # Token creation/validation
│   ├── test_session_handling.py     # Session management
│   └── test_vault_integration.py    # Vault client operations
├── security/                         # Security test suites
│   ├── test-auth-bypass.sh          # Authentication bypass attempts
│   ├── test-privilege-escalation.sh # Privilege escalation tests
│   └── test-token-abuse.sh          # Token abuse scenarios
└── performance/                      # Performance test suites
    ├── test-concurrent-auth.sh       # Concurrent authentication
    └── test-token-throughput.sh      # Token creation throughput
```

## 🚀 Running Tests

### Interactive Test Runner

The easiest way to run tests is using the interactive menu:

```bash
./tests/run-tests.sh
```

This provides a menu-driven interface:

```
╔════════════════════════════════════════╗
║      Enterprise OIDC Test Suite        ║
╠════════════════════════════════════════╣
║                                        ║
║  1. 🔐 Test Okta PKCE Authentication   ║
║  2. 🛠️  Test CLI Tools                 ║
║  3. 👥 Test Team Isolation             ║
║  4. 👤 Test User Identity              ║
║  5. 🚀 Run Full Workflow               ║
║  6. 🔒 Run Security Tests              ║
║  7. ⚡ Run Performance Tests           ║
║  8. 🧪 Run All Tests                   ║
║  9. 🔧 Debug Mode                      ║
║  9. ❌ Exit                            ║
║                                        ║
╚════════════════════════════════════════╝
```

### Command Line Execution

Run individual test suites directly:

```bash
# Test basic OIDC authentication with PKCE
./tests/integration/test-okta-auth.sh

# Test team access control and isolation
./tests/integration/test-team-isolation.sh

# Test user identity tracking and metadata
./tests/integration/test-user-identity.sh

# Test CLI tools functionality  
./tests/integration/test-cli-tools.sh

# Run comprehensive workflow test
./tests/integration/test-full-workflow.sh
```

### CLI Tools Testing

Specific tests for CLI authentication tools:

```bash
# Test comprehensive CLI tools functionality
./tests/integration/test-cli-tools.sh

# Individual tool testing manually:
# Test zero-dependency CLI tool (recommended)
./tools/bazel-auth-simple --help
./tools/bazel-auth-simple --no-browser  # Test PKCE flow initiation

# Test Python CLI tool (if dependencies available)
./tools/bazel-auth --help
pip install -r broker/requirements.txt  # Install dependencies first

# Test Bazel wrapper integration
./tools/bazel-build --help

# Manual PKCE flow testing
curl -X POST http://localhost:5000/cli/start  # Check PKCE parameters
```

### Environment Setup for Testing

Ensure proper environment configuration:

```bash
# Verify environment variables
if [ -z "$OKTA_DOMAIN" ]; then
    echo "❌ OKTA_DOMAIN not set"
    exit 1
fi

# Check service availability
curl -f http://localhost:8081/health || {
    echo "❌ Broker service not available"
    exit 1
}

# Verify Vault connectivity  
curl -f http://localhost:8200/v1/sys/health || {
    echo "❌ Vault service not available"
    exit 1
}

# Test CLI tools availability
./tools/bazel-auth-simple --help >/dev/null || {
    echo "❌ CLI tools not executable"
    exit 1
}
```

## 🔗 Integration Tests

### Test 1: Okta Authentication (`test-okta-auth.sh`)

**Purpose**: Verify complete OIDC authentication flow

**Test Steps**:
1. Check broker health and OIDC configuration
2. Verify Okta auth URL generation
3. Test session management endpoints
4. Validate token exchange process

```bash
#!/bin/bash
# tests/integration/test-okta-auth.sh

echo "🔐 Testing Okta OIDC Authentication Flow..."

# Test 1: Broker health check
echo "Testing broker health..."
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/health)
if [ "$response" != "200" ]; then
    echo "❌ Broker health check failed (HTTP $response)"
    exit 1
fi
echo "✅ Broker is healthy"

# Test 2: PKCE flow configuration
echo "Testing PKCE flow configuration..."
cli_start_response=$(curl -s -X POST http://localhost:8081/cli/start)
auth_url=$(echo "$cli_start_response" | jq -r '.auth_url // empty')
state=$(echo "$cli_start_response" | jq -r '.state // empty')

if [[ "$auth_url" != *"${OKTA_DOMAIN}"* ]]; then
    echo "❌ Okta auth URL not properly configured"
    echo "Expected domain: $OKTA_DOMAIN"
    echo "Actual response: $cli_start_response"
    exit 1
fi

if [[ "$auth_url" != *"code_challenge="* ]]; then
    echo "❌ PKCE code_challenge not found in auth URL"
    echo "Auth URL: $auth_url"
    exit 1
fi

if [[ "$auth_url" != *"code_challenge_method=S256"* ]]; then
    echo "❌ PKCE S256 method not configured"
    echo "Auth URL: $auth_url"
    exit 1
fi

echo "✅ PKCE authentication flow configured correctly"

# Test 3: CLI tools functionality
echo "Testing CLI tools..."
cli_help_output=$(./tools/bazel-auth-simple --help 2>&1)
if [[ "$cli_help_output" != *"PKCE"* ]]; then
    echo "⚠️  CLI help doesn't mention PKCE (may be outdated)"
fi

cli_url_output=$(./tools/bazel-auth-simple --no-browser 2>/dev/null | head -1)
if [[ "$cli_url_output" != *"Starting"* ]]; then
    echo "❌ CLI tool not generating authentication flow"
    exit 1
fi
echo "✅ CLI tools working correctly"

# Test 4: Session endpoint
echo "Testing session management..."
session_response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/exchange)
if [ "$session_response" != "405" ] && [ "$session_response" != "422" ]; then
    echo "❌ Session endpoint should return 405/422 for invalid requests"
    exit 1
fi
echo "✅ Session management working correctly"

echo "🎉 All OIDC authentication tests passed!"
```

### Test 2: Team Isolation (`test-team-isolation.sh`)

**Purpose**: Verify teams cannot access each other's secrets

**Test Steps**:
1. Create secrets for different teams
2. Verify team-specific access patterns
3. Test access denial for unauthorized teams
4. Validate audit logging

```bash
#!/bin/bash
# tests/integration/test-team-isolation.sh

echo "👥 Testing Team Access Isolation..."

# Setup test secrets
echo "Setting up team-specific test secrets..."

# Create mobile team secret
vault kv put kv/dev/mobile/test-secret \
    api_key="mobile-test-key-12345" \
    environment="test"

# Create backend team secret
vault kv put kv/dev/backend/test-secret \
    database_url="postgresql://test-backend-db" \
    api_token="backend-test-token-67890"

echo "✅ Test secrets created"

# Note: Actual team token testing requires interactive authentication
echo "📝 To complete this test:"
echo "1. Authenticate as mobile team member via browser"
echo "2. Verify access to kv/dev/mobile/* secrets only"
echo "3. Confirm denial of access to kv/dev/backend/* secrets"
echo "4. Repeat for backend team member"

echo "🔍 Manual verification required for complete team isolation testing"
```

### Test 3: User Identity (`test-user-identity.sh`)

**Purpose**: Verify individual user identity tracking

**Test Steps**:
1. Test user metadata in tokens
2. Verify audit trail contains user information
3. Check session user data
4. Validate entity assignment

```bash
#!/bin/bash
# tests/integration/test-user-identity.sh

echo "👤 Testing User Identity Tracking..."

# Test user session endpoint (requires authentication)
echo "Testing user identity endpoints..."

# Check session structure (unauthenticated will show expected format)
session_response=$(curl -s http://localhost:8081/session)
echo "Session response structure: $session_response"

echo "📝 To complete this test:"
echo "1. Authenticate via Okta OIDC flow"
echo "2. Check /session endpoint shows user email and groups"
echo "3. Verify /user/info contains complete user profile"
echo "4. Confirm audit logs show individual user attribution"

echo "🔍 Manual verification required for user identity testing"
```

### Test 4: Full Workflow (`test-full-workflow.sh`)

**Purpose**: Comprehensive end-to-end testing

**Test Steps**:
1. Complete authentication flow
2. Token exchange and validation
3. Secret access patterns
4. Session lifecycle management
5. Audit trail verification

```bash
#!/bin/bash
# tests/integration/test-full-workflow.sh

echo "🚀 Running Comprehensive Workflow Test..."

# Test 1: Service availability
echo "Step 1: Checking service availability..."
services=("http://localhost:8081/health" "http://localhost:8200/v1/sys/health")

for service in "${services[@]}"; do
    if ! curl -f -s "$service" > /dev/null; then
        echo "❌ Service unavailable: $service"
        exit 1
    fi
done
echo "✅ All services are available"

# Test 2: OIDC configuration
echo "Step 2: Validating OIDC configuration..."
oidc_config=$(curl -s "https://${OKTA_DOMAIN}/.well-known/openid_configuration")
if [ -z "$oidc_config" ]; then
    echo "❌ Cannot retrieve Okta OIDC configuration"
    exit 1
fi
echo "✅ Okta OIDC configuration accessible"

# Test 3: Vault OIDC setup
echo "Step 3: Checking Vault OIDC configuration..."
if ! vault auth list | grep -q "oidc"; then
    echo "❌ Vault OIDC auth method not enabled"
    exit 1
fi
echo "✅ Vault OIDC auth method configured"

# Test 4: Team policies
echo "Step 4: Verifying team policies..."
teams=("mobile-team" "backend-team" "frontend-team" "devops-team")

for team in "${teams[@]}"; do
    if ! vault policy read "$team" > /dev/null 2>&1; then
        echo "❌ Team policy missing: $team"
        exit 1
    fi
done
echo "✅ All team policies configured"

echo "🎉 Comprehensive workflow test completed successfully!"
echo "📝 Manual authentication testing required for complete validation"
```

## 🔬 Unit Testing

### Python Unit Tests

Unit tests are written using pytest and focus on individual components:

```python
# tests/unit/test_token_management.py
import pytest
from unittest.mock import Mock, patch
from broker.token_manager import TokenManager
from broker.exceptions import VaultAuthError

class TestTokenManager:
    
    @pytest.fixture
    def token_manager(self):
        return TokenManager(vault_url="http://test-vault:8200")
    
    @pytest.fixture
    def mock_vault_client(self):
        with patch('broker.token_manager.hvac.Client') as mock:
            yield mock.return_value
    
    @pytest.mark.asyncio
    async def test_create_team_token_success(self, token_manager, mock_vault_client):
        # Given
        user_info = {
            "email": "alice@company.com",
            "groups": ["mobile-developers"]
        }
        mock_vault_client.auth.oidc.login.return_value = {
            "auth": {
                "client_token": "hvs.EXAMPLE-TOKEN",
                "entity_id": "entity_123"
            }
        }
        
        # When
        result = await token_manager.create_team_token(user_info, "test-oidc-token")
        
        # Then
        assert result["token"] == "hvs.EXAMPLE-TOKEN"
        assert result["team"] == "mobile-team"
        assert result["user_email"] == "alice@company.com"
    
    @pytest.mark.asyncio
    async def test_create_team_token_vault_error(self, token_manager, mock_vault_client):
        # Given
        user_info = {"email": "alice@company.com", "groups": ["mobile-developers"]}
        mock_vault_client.auth.oidc.login.side_effect = Exception("Vault connection error")
        
        # When & Then
        with pytest.raises(VaultAuthError):
            await token_manager.create_team_token(user_info, "test-oidc-token")
    
    def test_map_groups_to_team(self, token_manager):
        # Test group to team mapping
        assert token_manager.map_groups_to_team(["mobile-developers"]) == "mobile-team"
        assert token_manager.map_groups_to_team(["backend-developers"]) == "backend-team"
        assert token_manager.map_groups_to_team(["devops-team"]) == "devops-team"
        
        # Test multiple groups (should return highest priority)
        assert token_manager.map_groups_to_team(["mobile-developers", "devops-team"]) == "devops-team"
```

### Session Management Tests

```python
# tests/unit/test_session_handling.py
import pytest
from unittest.mock import patch
from fastapi.testclient import TestClient
from broker.app import app

class TestSessionHandling:
    
    @pytest.fixture
    def client(self):
        return TestClient(app)
    
    def test_session_creation(self, client):
        # Test session creation after successful auth
        with patch('broker.app.exchange_oidc_token') as mock_exchange:
            mock_exchange.return_value = {
                "user_email": "test@company.com",
                "groups": ["mobile-developers"],
                "vault_token": "hvs.EXAMPLE"
            }
            
            response = client.post("/auth/callback", data={
                "code": "test-auth-code",
                "state": "test-state"
            })
            
            assert response.status_code == 302  # Redirect after auth
            assert "session_id" in response.cookies
    
    def test_session_validation(self, client):
        # Test session validation
        response = client.get("/session")
        assert response.status_code == 401  # No session
        
        # Mock authenticated session
        with client.session_transaction() as session:
            session["user_email"] = "test@company.com"
            session["vault_token"] = "hvs.EXAMPLE"
            session["expires_at"] = "2024-12-31T23:59:59Z"
        
        response = client.get("/session")
        assert response.status_code == 200
        assert response.json()["user_email"] == "test@company.com"
```

### Running Unit Tests

```bash
# Install test dependencies
pip install pytest pytest-asyncio pytest-mock

# Run all unit tests
cd tests && python -m pytest unit/ -v

# Run with coverage
python -m pytest unit/ --cov=broker --cov-report=html

# Run specific test file
python -m pytest unit/test_token_management.py -v

# Run with debug output
python -m pytest unit/ -v -s --log-cli-level=DEBUG
```

## ⚡ Performance Testing

### Concurrent Authentication Test

```bash
#!/bin/bash
# tests/performance/test-concurrent-auth.sh

echo "⚡ Testing Concurrent Authentication Performance..."

# Configuration
CONCURRENT_USERS=10
TEST_DURATION=60
BROKER_URL="http://localhost:8081"

# Function to simulate user authentication
simulate_auth() {
    local user_id=$1
    local start_time=$(date +%s)
    
    # Test auth URL generation
    auth_url=$(curl -s "$BROKER_URL/auth/url" | jq -r '.auth_url')
    if [[ "$auth_url" != *"okta.com"* ]]; then
        echo "❌ User $user_id: Auth URL generation failed"
        return 1
    fi
    
    # Test health endpoint
    health_response=$(curl -s -o /dev/null -w "%{http_code}" "$BROKER_URL/health")
    if [ "$health_response" != "200" ]; then
        echo "❌ User $user_id: Health check failed"
        return 1
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    echo "✅ User $user_id: Auth simulation completed in ${duration}s"
}

# Run concurrent simulations
echo "Starting $CONCURRENT_USERS concurrent authentication simulations..."
pids=()

for ((i=1; i<=CONCURRENT_USERS; i++)); do
    simulate_auth $i &
    pids+=($!)
done

# Wait for all simulations to complete
for pid in "${pids[@]}"; do
    wait $pid
done

echo "🎉 Concurrent authentication test completed"
```

### Token Throughput Test

```bash
#!/bin/bash
# tests/performance/test-token-throughput.sh

echo "🚀 Testing Token Creation Throughput..."

# Test parameters
REQUESTS_PER_SECOND=5
TOTAL_REQUESTS=50
BROKER_URL="http://localhost:8081"

# Function to test token endpoint performance
test_token_performance() {
    local request_id=$1
    local start_time=$(date +%s.%N)
    
    # Test auth URL endpoint (simulates token request)
    response=$(curl -s -w "HTTPSTATUS:%{http_code};TIME:%{time_total}" "$BROKER_URL/auth/url")
    
    local end_time=$(date +%s.%N)
    local http_code=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
    local time_total=$(echo "$response" | grep -o "TIME:[0-9.]*" | cut -d: -f2)
    
    if [ "$http_code" = "200" ]; then
        echo "✅ Request $request_id: Success (${time_total}s)"
    else
        echo "❌ Request $request_id: Failed (HTTP $http_code)"
    fi
}

# Run throughput test
echo "Testing $REQUESTS_PER_SECOND requests/second for $TOTAL_REQUESTS total requests..."

for ((i=1; i<=TOTAL_REQUESTS; i++)); do
    test_token_performance $i &
    
    # Rate limiting
    if (( i % REQUESTS_PER_SECOND == 0 )); then
        sleep 1
    fi
done

wait

echo "🎉 Token throughput test completed"
```

## 🔒 Security Testing

### Authentication Bypass Test

```bash
#!/bin/bash
# tests/security/test-auth-bypass.sh

echo "🔒 Testing Authentication Bypass Scenarios..."

BROKER_URL="http://localhost:8081"
VAULT_URL="http://localhost:8200"

# Test 1: Direct Vault access without authentication
echo "Test 1: Attempting direct Vault access..."
vault_response=$(curl -s -o /dev/null -w "%{http_code}" "$VAULT_URL/v1/kv/data/dev/mobile/test")
if [ "$vault_response" = "403" ] || [ "$vault_response" = "401" ]; then
    echo "✅ Vault properly denies unauthenticated access"
else
    echo "❌ Vault allows unauthenticated access (HTTP $vault_response)"
fi

# Test 2: Invalid session access
echo "Test 2: Testing invalid session handling..."
session_response=$(curl -s -H "Cookie: session_id=invalid-session" "$BROKER_URL/session")
if echo "$session_response" | grep -q "error\|unauthorized"; then
    echo "✅ Broker properly handles invalid sessions"
else
    echo "❌ Broker accepts invalid sessions"
fi

# Test 3: CSRF protection
echo "Test 3: Testing CSRF protection..."
csrf_response=$(curl -s -X POST "$BROKER_URL/auth/callback" -d "code=test&state=invalid")
if echo "$csrf_response" | grep -q "error\|invalid"; then
    echo "✅ CSRF protection active"
else
    echo "❌ Potential CSRF vulnerability"
fi

echo "🔐 Security tests completed"
```

### Privilege Escalation Test

```bash
#!/bin/bash
# tests/security/test-privilege-escalation.sh

echo "🛡️ Testing Privilege Escalation Protection..."

# Test 1: Team boundary enforcement
echo "Test 1: Testing team boundary enforcement..."
echo "📝 Manual test required:"
echo "1. Authenticate as mobile team member"
echo "2. Attempt to access backend team secrets"
echo "3. Verify access is denied"

# Test 2: Token scope verification
echo "Test 2: Token scope verification..."
echo "📝 Manual test required:"
echo "1. Obtain team token via authentication"
echo "2. Attempt to create additional tokens"
echo "3. Verify token creation is denied"

# Test 3: Admin operation blocking
echo "Test 3: Admin operation blocking..."
echo "📝 Manual test required:"
echo "1. Use team token to attempt admin operations"
echo "2. Try to modify Vault policies"
echo "3. Verify operations are denied"

echo "🔒 Privilege escalation tests completed"
```

## 🔧 Troubleshooting Tests

### Common Test Issues

#### 1. Service Unavailability

```bash
# Check if services are running
docker-compose ps

# Restart services if needed
docker-compose down && docker-compose up -d

# Check logs for errors
docker-compose logs broker
docker-compose logs vault
```

#### 2. Environment Configuration

```bash
# Verify environment variables
env | grep OKTA
env | grep VAULT

# Check .env file exists and is properly formatted
cat .env | grep -E '^[A-Z_]+=.*$'
```

#### 3. Network Connectivity

```bash
# Test broker connectivity
curl -f http://localhost:8081/health

# Test Vault connectivity  
curl -f http://localhost:8200/v1/sys/health

# Test Okta connectivity
curl -f "https://${OKTA_DOMAIN}/.well-known/openid_configuration"
```

#### 4. Authentication Flow Issues

```bash
# Check Okta configuration
echo "Domain: $OKTA_DOMAIN"
echo "Client ID: $OKTA_CLIENT_ID"
echo "Redirect URI: $OKTA_REDIRECT_URI"

# Verify Vault OIDC setup
vault auth list | grep oidc
vault read auth/oidc/config
```

### Test Data Cleanup

```bash
#!/bin/bash
# Clean up test data after tests

echo "Cleaning up test data..."

# Remove test secrets
vault kv delete kv/dev/mobile/test-secret
vault kv delete kv/dev/backend/test-secret
vault kv delete kv/dev/frontend/test-secret

# Clear test sessions (if applicable)
curl -X DELETE http://localhost:8081/admin/sessions/test

echo "✅ Test data cleanup completed"
```

### Debugging Failed Tests

1. **Enable Debug Logging**:
   ```bash
   export DEBUG=1
   export LOG_LEVEL=DEBUG
   ./tests/integration/test-okta-auth.sh
   ```

2. **Check Service Logs**:
   ```bash
   # Broker logs
   docker logs broker | tail -50
   
   # Vault logs
   docker logs vault | tail -50
   ```

3. **Manual API Testing**:
   ```bash
   # Test each endpoint manually
   curl -v http://localhost:8081/health
   curl -v http://localhost:8081/auth/url
   curl -v http://localhost:8200/v1/sys/health
   ```

## 📈 Test Metrics and Reporting

### Coverage Reports

```bash
# Generate test coverage report
python -m pytest tests/unit/ --cov=broker --cov-report=html --cov-report=term

# View coverage report
open htmlcov/index.html
```

### Performance Metrics

Key metrics to monitor during testing:

- **Authentication Latency**: < 2 seconds for full OIDC flow
- **Token Creation Time**: < 500ms for team token creation  
- **Concurrent Users**: Support 100+ concurrent authentications
- **Session Management**: < 100ms for session operations

### Test Automation

Integration with CI/CD:

```yaml
# .github/workflows/test.yml
name: Test Suite
on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup Python
        uses: actions/setup-python@v2
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: pip install -r broker/requirements.txt
      - name: Run unit tests
        run: python -m pytest tests/unit/ --cov=broker
  
  integration-tests:
    runs-on: ubuntu-latest
    needs: unit-tests
    steps:
      - uses: actions/checkout@v2
      - name: Start services
        run: docker-compose up -d
      - name: Run integration tests
        run: ./tests/run-tests.sh --automated
```

This comprehensive testing guide ensures the Enterprise OIDC Vault Demo maintains high quality, security, and performance standards. Regular execution of these tests helps catch issues early and maintains confidence in the system's reliability.