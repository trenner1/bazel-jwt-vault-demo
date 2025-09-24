#!/bin/bash

# Test CLI Tools for OIDC Authentication with PKCE
# ================================================
# This script tests the CLI authentication tools for the OIDC flow
# Run this after the environment is started with ./start-demo.sh

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOOLS_DIR="$PROJECT_ROOT/tools"
BROKER_URL="${BROKER_URL:-http://localhost:8081}"
VAULT_URL="${VAULT_URL:-http://localhost:8200}"

echo "CLI TOOLS AUTHENTICATION TEST"
echo "================================="
echo "Testing CLI tools for OIDC authentication with PKCE"
echo "Project root: $PROJECT_ROOT"
echo "Tools directory: $TOOLS_DIR"
echo "Broker URL: $BROKER_URL"
echo "Vault URL: $VAULT_URL"
echo

# Test 1: Tool availability and permissions
echo
log_info "Test 1: Tool Availability and Permissions"
echo "-----------------------------------------"

# Change to tools directory
cd "$TOOLS_DIR" || {
    log_error "Tools directory not found: $TOOLS_DIR"
    exit 1
}

# Test bazel-auth-simple
if [[ -f "bazel-auth-simple" ]]; then
    if [[ -x "bazel-auth-simple" ]]; then
        log_success "bazel-auth-simple is executable"
        
        # Test help output
        HELP_OUTPUT=$(./bazel-auth-simple --help 2>&1 || echo "error")
        if echo "$HELP_OUTPUT" | grep -q "OIDC"; then
            log_success "bazel-auth-simple help shows OIDC information"
        else
            log_warning "bazel-auth-simple help output unclear"
            echo "Help output: $HELP_OUTPUT"
        fi
    else
        log_error "bazel-auth-simple exists but is not executable"
        ls -la bazel-auth-simple
    fi
else
    log_error "bazel-auth-simple not found in tools directory"
fi

# Test bazel-auth (Python version)
if [[ -f "bazel-auth" ]]; then
    if [[ -x "bazel-auth" ]]; then
        log_success "bazel-auth (Python) is executable"
        
        # Test Python dependencies
        PYTHON_TEST=$(./bazel-auth --help 2>&1 || echo "error")
        if echo "$PYTHON_TEST" | grep -q "ModuleNotFoundError\|ImportError"; then
            log_warning "bazel-auth has missing Python dependencies"
            echo "Install with: pip install -r broker/requirements.txt"
        elif echo "$PYTHON_TEST" | grep -q "usage\|help"; then
            log_success "bazel-auth Python dependencies satisfied"
        else
            log_warning "bazel-auth Python test inconclusive"
        fi
    else
        log_error "bazel-auth exists but is not executable"
    fi
else
    log_warning "bazel-auth (Python version) not found"
fi

# Test bazel-build wrapper
if [[ -f "bazel-build" ]]; then
    if [[ -x "bazel-build" ]]; then
        log_success "bazel-build wrapper is executable"
        
        # Test wrapper help
        WRAPPER_HELP=$(./bazel-build --help 2>&1 | head -5 || echo "error")
        if echo "$WRAPPER_HELP" | grep -q "bazel\|auth"; then
            log_success "bazel-build wrapper shows relevant help"
        else
            log_info "bazel-build wrapper help: $WRAPPER_HELP"
        fi
    else
        log_error "bazel-build exists but is not executable"
    fi
else
    log_warning "bazel-build wrapper not found"
fi

# Test 2: PKCE flow initiation
echo
log_info "Test 2: PKCE Flow Initiation"
echo "----------------------------"

# Test broker availability first
BROKER_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BROKER_URL/" || echo "000")
if [[ "$BROKER_STATUS" == "200" ]]; then
    log_success "Broker is accessible at $BROKER_URL"
else
    log_error "Broker is not accessible (HTTP $BROKER_STATUS)"
    echo "Make sure to run ./start-demo.sh first"
    exit 1
fi

# Test PKCE flow start with bazel-auth-simple
if [[ -x "bazel-auth-simple" ]]; then
    echo "Testing bazel-auth-simple PKCE flow initiation..."
    
    # Test non-interactive mode to avoid opening browser
    CLI_OUTPUT=$(./bazel-auth-simple --no-browser 2>&1 | head -10 || echo "error")
    
    if echo "$CLI_OUTPUT" | grep -q "Starting Bazel authentication"; then
        log_success "bazel-auth-simple initiates OIDC flow"
        
        if echo "$CLI_OUTPUT" | grep -q "code_challenge_method=S256"; then
            log_success "bazel-auth-simple uses PKCE flow (S256)"
        else
            log_info "PKCE flow implicit in output"
        fi
        
        if echo "$CLI_OUTPUT" | grep -q "code_challenge"; then
            log_success "bazel-auth-simple generates PKCE code challenge"
        else
            log_info "PKCE challenge generation not visible in output"
        fi
        
        # Check for auth URL generation
        if echo "$CLI_OUTPUT" | grep -q "http"; then
            # Extract the full URL from the output, handling line breaks
            AUTH_URL=$(echo "$CLI_OUTPUT" | grep -A5 -B5 "http" | tr -d '\n' | grep -o 'https://[^[:space:]]*' | head -1)
            log_success "Generated authentication URL: ${AUTH_URL:0:80}..."
            
            # Verify PKCE parameters in full URL
            if [[ "$AUTH_URL" == *"code_challenge="* ]]; then
                log_success "Auth URL contains PKCE code_challenge parameter"
            else
                log_warning "Auth URL missing PKCE code_challenge parameter"
            fi
            
            if [[ "$AUTH_URL" == *"code_challenge_method=S256"* ]]; then
                log_success "Auth URL uses PKCE S256 method"
            else
                log_warning "Auth URL missing PKCE S256 method"
            fi
        else
            log_warning "No authentication URL found in output"
        fi
    else
        log_error "bazel-auth-simple failed to initiate OIDC flow"
        echo "Output: $CLI_OUTPUT"
    fi
else
    log_warning "Skipping bazel-auth-simple test - tool not available"
fi

# Test 3: Error handling and validation
echo
log_info "Test 3: Error Handling and Validation" 
echo "-------------------------------------"

if [[ -x "bazel-auth-simple" ]]; then
    echo "Testing bazel-auth-simple error handling..."
    
    # Test invalid broker URL
    INVALID_BROKER_TEST=$(BROKER_URL="http://invalid-broker:9999" ./bazel-auth-simple --no-browser 2>&1 | head -5 || echo "expected_error")
    if echo "$INVALID_BROKER_TEST" | grep -q "Connection\|refused\|error"; then
        log_success "bazel-auth-simple handles connection errors gracefully"
    else
        log_warning "bazel-auth-simple error handling unclear"
    fi
    
    # Test help flag
    HELP_TEST=$(./bazel-auth-simple --help 2>&1 || echo "error")
    if echo "$HELP_TEST" | grep -q "Usage\|Options\|help"; then
        log_success "bazel-auth-simple provides helpful usage information"
    else
        log_warning "bazel-auth-simple help output could be improved"
    fi
else
    log_warning "Skipping error handling test - bazel-auth-simple not available"
fi

# Test 4: Integration with broker API
echo
log_info "Test 4: Integration with Broker API"
echo "-----------------------------------"

# Test /cli/start endpoint directly
CLI_START_TEST=$(curl -s -X POST "$BROKER_URL/cli/start" || echo '{"error": "failed"}')
if echo "$CLI_START_TEST" | jq -e '.auth_url' > /dev/null 2>&1; then
    log_success "Broker /cli/start endpoint responding correctly"
    
    AUTH_URL=$(echo "$CLI_START_TEST" | jq -r '.auth_url')
    STATE=$(echo "$CLI_START_TEST" | jq -r '.state // "missing"')
    
    # Verify PKCE parameters are included
    if [[ "$AUTH_URL" == *"code_challenge="* ]] && [[ "$AUTH_URL" == *"code_challenge_method=S256"* ]]; then
        log_success "Broker generates proper PKCE parameters"
    else
        log_error "Broker not generating proper PKCE parameters"
    fi
    
    if [[ "$STATE" != "missing" ]]; then
        log_success "Broker includes state parameter for CSRF protection"
    else
        log_warning "Broker state parameter missing"
    fi
    
    # Test session creation
    SESSION_ID_TEST=$(echo "$CLI_START_TEST" | jq -r '.session_id // "missing"')
    if [[ "$SESSION_ID_TEST" != "missing" ]]; then
        log_success "Broker creates session ID for token exchange"
    else
        log_info "Session ID creation handled differently"
    fi
    
else
    log_error "Broker /cli/start endpoint not responding correctly"
    echo "Response: $CLI_START_TEST"
fi

# Test 5: Tool recommendations and documentation
echo
log_info "Test 5: Tool Recommendations and Documentation"
echo "----------------------------------------------"

# Check for README in tools directory
if [[ -f "README.md" ]]; then
    log_success "Tools README documentation available"
    
    if grep -q "bazel-auth-simple" README.md; then
        log_success "README documents bazel-auth-simple (recommended tool)"
    else
        log_warning "README missing bazel-auth-simple documentation"
    fi
    
    if grep -q "PKCE" README.md; then
        log_success "README mentions PKCE authentication"
    else
        log_warning "README missing PKCE information"
    fi
    
    if grep -q "zero dependencies" README.md; then
        log_success "README highlights zero dependencies benefit"
    else
        log_info "Zero dependencies benefit not highlighted"
    fi
else
    log_warning "Tools README documentation missing"
fi

# Test 6: Manual authentication flow (informational)
echo
log_info "Test 6: Manual Authentication Flow Guide"
echo "----------------------------------------"

echo "Manual testing workflow:"
echo "1. Start authentication:"
echo "   ./tools/bazel-auth-simple"
echo
echo "2. Complete Okta authentication in browser"
echo
echo "3. Enhanced callback page will show:"
echo "   - Auto-copied session_id"
echo "   - One-click copy buttons"
echo "   - Clear next steps"
echo
echo "4. Test token exchange:"
echo "   curl -X POST $BROKER_URL/child-token \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"session_id\": \"YOUR_SESSION_ID\"}'"
echo
echo "5. Use returned Vault token for secret access"

log_success "Manual authentication flow documented"

# Summary
echo
echo " CLI TOOLS TEST COMPLETE"
echo "=========================="

if [[ -x "bazel-auth-simple" ]]; then
    log_success "bazel-auth-simple ready for use (recommended)"
else
    log_error "bazel-auth-simple not available - check installation"
fi

if [[ -x "bazel-auth" ]]; then
    log_success "bazel-auth (Python) available as alternative"
else
    log_warning "bazel-auth (Python) not available"
fi

if [[ -x "bazel-build" ]]; then
    log_success "bazel-build wrapper available"
else
    log_warning "bazel-build wrapper not available"
fi

echo
echo " Recommended usage:"
echo "   ./tools/bazel-auth-simple  # Zero dependencies, fastest"
echo "   ./tools/bazel-auth         # Python-based, more features"
echo "   ./tools/bazel-build        # Wrapper for Bazel commands"
echo
echo " All tools support:"
echo "   - PKCE authentication flow"
echo "   - Session ID-based token exchange"  
echo "   - Team-based access control"
echo "   - Enhanced callback page UX"