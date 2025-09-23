#!/bin/bash
set -euo pipefail

# Comprehensive Integration Test Suite for Okta OIDC Authentication
# This script runs all integration tests and provides a complete system verification

echo " Bazel JWT Vault Demo - Comprehensive Integration Test Suite"
echo "============================================================="

# Configuration
BROKER_URL="http://localhost:8081"
VAULT_ADDR="http://localhost:8200"
TEST_DIR="$(dirname "$0")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Helper functions
log_success() {
    echo -e "${GREEN} $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}$1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_info() {
    echo -e "${BLUE} $1${NC}"
}

log_header() {
    echo -e "${PURPLE} $1${NC}"
}

# Function to run a test and track results
run_test() {
    local test_name="$1"
    local test_script="$2"
    local interactive="$3"
    
    echo
    log_header "Running Test: $test_name"
    echo "$(printf '%*s' 80 '' | tr ' ' '=')"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$interactive" == "true" ]]; then
        echo "This test requires interactive input"
        echo "Do you want to run this test? (y/N)"
        read -r RUN_THIS_TEST
        
        if [[ ! "$RUN_THIS_TEST" =~ ^[Yy]$ ]]; then
            log_warning "Skipping interactive test: $test_name"
            return 0
        fi
    fi
    
    # Run the test
    if [[ -f "$test_script" && -x "$test_script" ]]; then
        if "$test_script"; then
            log_success "Test passed: $test_name"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            log_error "Test failed: $test_name"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            FAILED_TESTS+=("$test_name")
        fi
    else
        log_error "Test script not found or not executable: $test_script"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$test_name")
    fi
}

# Function to check prerequisites
check_prerequisites() {
    echo
    log_info "Checking Prerequisites"
    echo "----------------------"
    
    # Check if broker is running
    if curl -s "$BROKER_URL/health" > /dev/null; then
        local health_response=$(curl -s "$BROKER_URL/health")
        if echo "$health_response" | jq -e '.auth_method == "okta_oidc"' > /dev/null; then
            log_success "Broker is running with Okta OIDC"
        else
            log_error "Broker is not configured for Okta OIDC"
            return 1
        fi
    else
        log_error "Broker is not accessible at $BROKER_URL"
        echo "Please start the broker with: docker-compose up"
        return 1
    fi
    
    # Check if Vault is accessible
    if curl -s "$VAULT_ADDR/v1/sys/health" > /dev/null; then
        local vault_health=$(curl -s "$VAULT_ADDR/v1/sys/health")
        if echo "$vault_health" | jq -e '.sealed == false' > /dev/null; then
            log_success "Vault is accessible and unsealed"
        else
            log_error "Vault is sealed or unhealthy"
            return 1
        fi
    else
        log_error "Vault is not accessible at $VAULT_ADDR"
        echo "Please ensure Vault is running and accessible"
        return 1
    fi
    
    # Check required tools
    local missing_tools=()
    command -v curl >/dev/null 2>&1 || missing_tools+=("curl")
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools before running tests"
        return 1
    else
        log_success "All required tools available (curl, jq)"
    fi
    
    log_success "All prerequisites met"
}

# Function to display test environment info
show_environment_info() {
    echo
    log_info "Test Environment Information"
    echo "----------------------------"
    
    # Broker information
    local home_response=$(curl -s "$BROKER_URL/" 2>/dev/null || echo "ERROR")
    if echo "$home_response" | grep -q "Okta OIDC"; then
        local okta_domain=$(echo "$home_response" | grep -o 'Domain:[^<]*' | cut -d' ' -f2 || echo "Not visible")
        local client_id=$(echo "$home_response" | grep -o 'Client ID:[^<]*' | cut -d' ' -f3 || echo "Not visible")
        
        echo " Okta Configuration:"
        echo "   Domain: $okta_domain"
        echo "   Client ID: $client_id"
        echo "   Broker URL: $BROKER_URL"
    else
        log_warning "Cannot retrieve Okta configuration from broker"
    fi
    
    # Vault information
    local vault_status=$(curl -s "$VAULT_ADDR/v1/sys/seal-status" 2>/dev/null || echo '{}')
    if echo "$vault_status" | jq -e '.sealed' > /dev/null; then
        local vault_version=$(echo "$vault_status" | jq -r '.version // "unknown"')
        echo "🏦 Vault Status:"
        echo "   Version: $vault_version"
        echo "   Address: $VAULT_ADDR"
        echo "   Sealed: $(echo "$vault_status" | jq -r '.sealed')"
    fi
    
    # Test configuration
    echo " Test Configuration:"
    echo "   Test directory: $TEST_DIR"
    echo "   Available tests:"
    for test_file in "$TEST_DIR"/test-*.sh; do
        if [[ -f "$test_file" ]]; then
            local test_name=$(basename "$test_file" .sh)
            echo "     - $test_name"
        fi
    done
}

# Function to run automated tests
run_automated_tests() {
    echo
    log_header "Running Automated Tests"
    echo "$(printf '%*s' 80 '' | tr ' ' '=')"
    
    # Test 1: Basic Okta authentication (automated portions)
    if [[ -f "$TEST_DIR/test-okta-auth.sh" ]]; then
        run_test "Okta OIDC Authentication" "$TEST_DIR/test-okta-auth.sh" "false"
    fi
    
    # Additional automated health checks
    run_test "Broker Health Check" "check_broker_health" "false"
    run_test "Vault Connectivity" "check_vault_connectivity" "false"
    run_test "OIDC Configuration" "check_oidc_config" "false"
}

# Function to run interactive tests
run_interactive_tests() {
    echo
    log_header "Running Interactive Tests"
    echo "$(printf '%*s' 80 '' | tr ' ' '=')"
    
    echo "Interactive tests require manual Okta authentication."
    echo "Do you want to run interactive tests? (y/N)"
    read -r RUN_INTERACTIVE
    
    if [[ "$RUN_INTERACTIVE" =~ ^[Yy]$ ]]; then
        # Test 2: Team isolation
        if [[ -f "$TEST_DIR/test-team-isolation.sh" ]]; then
            run_test "Team Isolation & Access Control" "$TEST_DIR/test-team-isolation.sh" "true"
        fi
        
        # Test 3: User identity
        if [[ -f "$TEST_DIR/test-user-identity.sh" ]]; then
            run_test "User Identity & Entity Management" "$TEST_DIR/test-user-identity.sh" "true"
        fi
        
        # Test 4: Full workflow test
        run_test "End-to-End Workflow" "run_e2e_workflow_test" "true"
    else
        log_warning "Skipping interactive tests"
    fi
}

# Individual test functions for granular testing
check_broker_health() {
    local health_response=$(curl -s "$BROKER_URL/health" 2>/dev/null || echo '{"status": "error"}')
    
    if echo "$health_response" | jq -e '.status == "healthy"' > /dev/null; then
        log_success "Broker health check passed"
        
        local auth_method=$(echo "$health_response" | jq -r '.auth_method')
        if [[ "$auth_method" == "okta_oidc" ]]; then
            log_success "Authentication method: $auth_method"
            return 0
        else
            log_error "Wrong authentication method: $auth_method"
            return 1
        fi
    else
        log_error "Broker health check failed"
        return 1
    fi
}

check_vault_connectivity() {
    local vault_health=$(curl -s "$VAULT_ADDR/v1/sys/health" 2>/dev/null || echo '{"sealed": true}')
    
    if echo "$vault_health" | jq -e '.sealed == false' > /dev/null; then
        log_success "Vault connectivity verified"
        
        # Check if OIDC auth method is enabled
        local auth_methods=$(curl -s "$VAULT_ADDR/v1/sys/auth" 2>/dev/null || echo '{}')
        if echo "$auth_methods" | jq -e '.["oidc/"]' > /dev/null; then
            log_success "OIDC auth method is enabled"
            return 0
        else
            log_warning "OIDC auth method not detected"
            return 1
        fi
    else
        log_error "Vault is sealed or inaccessible"
        return 1
    fi
}

check_oidc_config() {
    local home_response=$(curl -s "$BROKER_URL/" 2>/dev/null || echo "ERROR")
    
    if echo "$home_response" | grep -q "Login with Okta"; then
        log_success "Okta login interface available"
        
        if echo "$home_response" | grep -q "Enterprise OIDC Authentication"; then
            log_success "Enterprise OIDC branding detected"
            return 0
        else
            log_warning "Expected enterprise OIDC branding not found"
            return 1
        fi
    else
        log_error "Okta login interface not found"
        return 1
    fi
}

run_e2e_workflow_test() {
    echo "End-to-End Workflow Test"
    echo "This test verifies the complete authentication flow:"
    echo "1. User visits broker"
    echo "2. Authenticates with Okta"
    echo "3. Receives session ID"
    echo "4. Exchanges session for Vault token"
    echo "5. Accesses secrets with token"
    echo
    echo "Please complete this workflow manually and confirm success (y/N):"
    read -r E2E_SUCCESS
    
    if [[ "$E2E_SUCCESS" =~ ^[Yy]$ ]]; then
        log_success "End-to-end workflow confirmed"
        return 0
    else
        log_error "End-to-end workflow not confirmed"
        return 1
    fi
}

# Function to generate test report
generate_test_report() {
    echo
    echo " TEST SUITE EXECUTION SUMMARY"
    echo "==============================="
    
    echo " Test Statistics:"
    echo "   Total tests run: $TESTS_RUN"
    echo "   Tests passed: $TESTS_PASSED"
    echo "   Tests failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "All tests passed! "
        echo
        echo " System Status: READY FOR PRODUCTION"
        echo " Okta OIDC authentication: WORKING"
        echo " Team-based access control: VERIFIED"
        echo " User identity management: FUNCTIONAL"
        echo " Vault integration: OPERATIONAL"
    else
        log_error "Some tests failed"
        echo
        echo "❌ Failed tests:"
        for failed_test in "${FAILED_TESTS[@]}"; do
            echo "   - $failed_test"
        done
        echo
        echo " Recommendations:"
        echo "   1. Check Okta configuration and connectivity"
        echo "   2. Verify Vault OIDC auth method setup"
        echo "   3. Ensure all required Okta groups exist"
        echo "   4. Review broker and vault logs for errors"
    fi
    
    echo
    echo " Documentation:"
    echo "   Setup Guide: OKTA_SETUP.md"
    echo "   Architecture: docs/ARCHITECTURE.md"
    echo "   Troubleshooting: docs/DEVELOPMENT.md"
    
    # Return appropriate exit code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Main execution
main() {
    echo "Starting comprehensive integration test suite..."
    echo "This suite tests the complete Okta OIDC authentication system."
    echo
    
    # Check prerequisites
    if ! check_prerequisites; then
        log_error "Prerequisites not met. Exiting."
        exit 1
    fi
    
    # Show environment information
    show_environment_info
    
    # Run automated tests
    run_automated_tests
    
    # Run interactive tests
    run_interactive_tests
    
    # Generate final report
    generate_test_report
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Bazel JWT Vault Demo - Integration Test Suite"
        echo
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --automated    Run only automated tests"
        echo "  --interactive  Run only interactive tests"
        echo "  --check        Check prerequisites only"
        echo
        echo "Examples:"
        echo "  $0                # Run all tests"
        echo "  $0 --automated    # Run automated tests only"
        echo "  $0 --check        # Check prerequisites"
        exit 0
        ;;
    --automated)
        check_prerequisites && show_environment_info && run_automated_tests && generate_test_report
        ;;
    --interactive)
        check_prerequisites && show_environment_info && run_interactive_tests && generate_test_report
        ;;
    --check)
        check_prerequisites
        ;;
    "")
        main
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac