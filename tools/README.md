# Developer Tools for Bazel Authentication

This directory contains user-friendly tools to simplify the **Okta OIDC authentication flow** for Bazel builds using **Authorization Code Flow with PKCE**.

## 🚀 Quick Start

### 1. Zero-Dependency Authentication (Recommended)
```bash
# Authenticate using the simple CLI tool (requires only curl)
./tools/bazel-auth-simple

# Follow the prompts:
# 1. Browser opens automatically for Okta login
# 2. Complete authentication and copy session ID
# 3. Run the provided command to get your token

# Export token for immediate use
eval $(./tools/bazel-auth-simple --session-id SESSION_ID --export)
echo $VAULT_TOKEN
```

### 2. Seamless Bazel Builds
```bash
# Authenticate automatically and run your build
./tools/bazel-build build //my:target

# Run tests with authentication
./tools/bazel-build test //my:tests

# Include pipeline metadata for better tracking
./tools/bazel-build --pipeline ci-main build //my:target
```

## 🛠️ Tools Overview

### `bazel-auth-simple` - Zero-Dependency CLI ⭐
**Recommended for most use cases**

A shell-based tool that works anywhere with just `curl`.

**Features:**
- ✅ **Zero dependencies** - Only needs `curl` (available everywhere)
- ✅ **Auto-browser opening** - Automatically opens authentication URL
- ✅ **Enhanced web UI** - Beautiful callback page with copy buttons
- ✅ **Multiple output formats** - Token-only, export command, or full details
- ✅ **PKCE security** - Uses Authorization Code Flow with PKCE

**Usage:**
```bash
./tools/bazel-auth-simple                           # Interactive auth with auto-browser
./tools/bazel-auth-simple --no-browser              # Get auth URL without opening browser
./tools/bazel-auth-simple --session-id SESSION_ID   # Exchange session for token
./tools/bazel-auth-simple --session-id SESSION_ID --export   # Get export command
```

### `bazel-auth` - Full-Featured CLI (Requires Dependencies)
**Note: Requires Python dependencies - use `bazel-auth-simple` instead**

A Python-based tool with advanced features, but requires `requests` module.

**Installation:**
```bash
pip install requests  # Required dependency
```

**Features:**
- 🐍 **Python-based** - Full-featured but requires dependencies
- 🔄 **Local server callback** - Automatic callback handling
- 📊 **Rich output** - Detailed status and progress information

**Usage:**
```bash
./tools/bazel-auth --export           # Output export command for eval
./tools/bazel-auth --token-only       # Just output the token
./tools/bazel-auth --no-browser       # Manual flow (no auto-open)
./tools/bazel-auth --pipeline my-app  # Include custom metadata
```

**⚠️ Limitation**: This tool requires the `requests` Python module. For zero-dependency usage, use `bazel-auth-simple` instead.

### `bazel-build` - Bazel Wrapper with Authentication
A bash wrapper that combines authentication with Bazel execution.

**Features:**
- 🔐 **Automatic authentication** - Handles auth flow before running Bazel
- ⚡ **Smart token reuse** - Detects existing tokens and offers to reuse
- 🏷️ **Metadata integration** - Automatically includes pipeline/repo information
- 🛠️ **Full Bazel compatibility** - Passes through all Bazel commands and flags

**Usage:**
```bash
./tools/bazel-build build //my:target              # Auth + build
./tools/bazel-build test //my:tests                # Auth + test
./tools/bazel-build --no-auth build //my:target    # Skip auth
./tools/bazel-build --pipeline ci //my:target      # Custom metadata
```

## 🔐 Authentication Flow (PKCE)

1. **Start**: Tool initiates Authorization Code Flow with PKCE
2. **Browser**: Automatically opens Okta authentication URL
3. **Login**: User completes Okta authentication with credentials
4. **Callback**: Browser redirects to enhanced callback page with session ID
5. **Session**: Session ID is displayed with auto-copy functionality
6. **Exchange**: Tool exchanges session for team-scoped Vault token
7. **Ready**: Token is set in environment for immediate use

## 🎨 Enhanced Developer Experience

### Auto-Copy Clipboard Support
The enhanced callback page automatically:
- 📋 Copies session ID to clipboard on page load
- 🖱️ Provides one-click copy buttons for all commands
- 📝 Shows ready-to-use curl commands with session ID populated
- 🚀 Includes CLI tool usage examples with correct session ID

### Intelligent Token Management
- ♻️ **Reuse detection**: Warns if token already exists in environment
- ⏰ **TTL awareness**: Shows token expiration and usage information
- 👥 **Team context**: Displays user teams and assigned permissions
- 🏷️ **Metadata tracking**: Includes pipeline, repo, and target information
- 🔍 **Metadata tracking**: Includes pipeline and build context

### Error Handling & Recovery
- 🔄 **Automatic retries** for network issues
- 📊 **Clear error messages** with suggested fixes
- 🚨 **Graceful fallbacks** to manual mode if auto-flow fails
- 📋 **Detailed logging** with `--verbose` flag

## Configuration

### Environment Variables
```bash
export BROKER_URL="http://localhost:8081"    # Broker service URL
export PIPELINE="my-pipeline"                # Default pipeline name
export REPO="my-repo"                       # Default repository name
```

### Dependencies
```bash
# Install Python dependencies
pip3 install -r tools/requirements.txt

# Or manually install requests
pip3 install requests
```

## Examples

### CI/CD Integration
```bash
#!/bin/bash
# In your CI pipeline
eval $(./tools/bazel-auth --export --pipeline "${CI_PIPELINE_NAME}")
bazel build //...
bazel test //...
```

### Development Workflow
```bash
# Start of day - get authenticated once
eval $(./tools/bazel-auth --export)

# Now run multiple builds without re-auth
bazel build //backend:server
bazel test //backend:tests
bazel build //frontend:app
```

### Team-Specific Builds
```bash
# Mobile team member
./tools/bazel-build --pipeline mobile-release build //mobile:app

# Backend team member  
./tools/bazel-build --pipeline backend-api build //backend:services

# DevOps with full access
./tools/bazel-build --pipeline infrastructure build //...
```

## Troubleshooting

### Common Issues

**"Connection failed" errors:**
```bash
# Check if broker is running
curl http://localhost:8081/health

# Check Docker containers
docker ps | grep bazel-broker
```

**"Invalid session" errors:**
```bash
# Sessions expire after 1 hour, re-authenticate
./tools/bazel-auth --export
```

**Browser doesn't open:**
```bash
# Use manual mode
./tools/bazel-auth --no-browser
```

**Python dependencies missing:**
```bash
# Install requirements
pip3 install -r tools/requirements.txt
```

### Debug Mode
```bash
# Enable verbose logging
./tools/bazel-auth --verbose
./tools/bazel-build --verbose build //my:target
```

## Advanced Usage

### Custom Callback Handling
The `bazel-auth` tool can run a local callback server on a different port if 8082 is busy:

```bash
# Tool automatically finds available port
./tools/bazel-auth  # Uses port 8082, 8083, etc.
```

### Token Inspection
```bash
# Get token details
VAULT_TOKEN=$(./tools/bazel-auth --token-only)
echo "Token: ${VAULT_TOKEN:0:20}..."

# Check token metadata (requires vault CLI)
vault token lookup
```

### Integration with Other Tools
```bash
# Use with any command that needs VAULT_TOKEN
eval $(./tools/bazel-auth --export)
curl -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/secret/my-app"

# Use in scripts
export VAULT_TOKEN=$(./tools/bazel-auth --token-only)
my-custom-build-script.sh
```