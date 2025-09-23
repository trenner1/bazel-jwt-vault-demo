#!/bin/bash
set -euo pipefail

# Test Runner for Bazel JWT Vault Demo
# Simplified interface for running all integration tests

echo " Bazel JWT Vault Demo - Test Runner"
echo "====================================="

TEST_DIR="$(dirname "$0")/integration"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE} $1${NC}"
}

log_success() {
    echo -e "${GREEN} $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}$1${NC}"
}

# Menu function
show_menu() {
    echo
    log_info "Available Test Suites:"
    echo "1.  Okta Authentication Test (automated)"
    echo "2. �  CLI Tools Test (automated)"
    echo "3. � Team Isolation Test (interactive)"
    echo "4.  User Identity Test (interactive)"
    echo "5.  Full Workflow Test (comprehensive)"
    echo "6.  Run All Tests"
    echo "7. ❓ Help & Documentation"
    echo "0. Exit"
    echo
}

run_single_test() {
    local test_file="$1"
    local test_name="$2"
    
    if [[ -f "$test_file" && -x "$test_file" ]]; then
        echo
        log_info "Running: $test_name"
        echo "$(printf '%*s' 50 '' | tr ' ' '-')"
        "$test_file"
    else
        echo "❌ Test file not found: $test_file"
    fi
}

show_help() {
    echo
    log_info "Test Documentation"
    echo
    echo " Test Descriptions:"
    echo
    echo " Okta Authentication Test:"
    echo "   - Validates OIDC integration with Okta and PKCE flow"
    echo "   - Tests broker endpoints and enhanced callback page"
    echo "   - Verifies session management and token exchange"
    echo "   - Can run automated validation + optional interactive test"
    echo
    echo "CLI Tools Test:"
    echo "   - Tests bazel-auth-simple (zero dependencies, recommended)"
    echo "   - Validates PKCE flow initiation from CLI tools"
    echo "   - Checks error handling and integration with broker API"
    echo "   - Verifies tool availability and proper configuration"
    echo
    echo " Team Isolation Test:"
    echo "   - Tests Okta group-based team access control"
    echo "   - Verifies team-specific secret access patterns"
    echo "   - Validates cross-team access restrictions"
    echo "   - Requires authentication as different team members"
    echo
    echo " User Identity Test:"
    echo "   - Tests user-specific identity tracking"
    echo "   - Verifies entity reuse for same user"
    echo "   - Tests user-specific secret paths"
    echo "   - Validates metadata preservation"
    echo
    echo " Full Workflow Test:"
    echo "   - Comprehensive end-to-end system verification"
    echo "   - Runs all automated tests plus additional checks"
    echo "   - Provides complete system health assessment"
    echo "   - Generates detailed test report"
    echo
    echo " Prerequisites:"
    echo "   - Docker Compose running (broker and vault-setup services)"
    echo "   - Okta developer account configured"
    echo "   - Required Okta groups created (mobile-developers, etc.)"
    echo "   - Test users assigned to appropriate groups"
    echo
    echo " Setup Commands:"
    echo "   docker-compose up       # Start services"
    echo "   ./tests/run-tests.sh    # Run this test runner"
    echo
}

# Main menu loop
while true; do
    show_menu
    echo -n "Select an option (0-6): "
    read -r choice
    
    case $choice in
        1)
            run_single_test "$TEST_DIR/test-okta-auth.sh" "Okta Authentication Test"
            ;;
        2)
            run_single_test "$TEST_DIR/test-cli-tools.sh" "CLI Tools Test"
            ;;
        3)
            run_single_test "$TEST_DIR/test-team-isolation.sh" "Team Isolation Test"
            ;;
        4)
            run_single_test "$TEST_DIR/test-user-identity.sh" "User Identity Test"
            ;;
        5)
            run_single_test "$TEST_DIR/test-full-workflow.sh" "Full Workflow Test"
            ;;
        6)
            echo
            log_info "Running All Tests"
            echo "$(printf '%*s' 50 '' | tr ' ' '=')"
            
            # Run comprehensive test suite
            if [[ -f "$TEST_DIR/test-full-workflow.sh" ]]; then
                "$TEST_DIR/test-full-workflow.sh"
            else
                echo "❌ Comprehensive test suite not found"
            fi
            ;;
        7)
            show_help
            ;;
        0)
            echo
            log_success "Thanks for testing! 👋"
            exit 0
            ;;
        *)
            echo "❌ Invalid option. Please select 0-7."
            ;;
    esac
    
    echo
    echo "Press Enter to continue..."
    read -r
done