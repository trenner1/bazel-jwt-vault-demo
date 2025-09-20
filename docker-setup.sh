#!/usr/bin/env bash
set -euo pipefail

# Bazel JWT Vault Demo - Docker Setup Script

echo "🚀 Bazel JWT Vault Demo - Docker Setup"
echo "======================================="

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check for existing Vault instance
EXISTING_VAULT=$(docker ps --filter "name=vault" --format "{{.Names}}" | head -1 || echo "")

if [[ -n "$EXISTING_VAULT" ]]; then
    echo "📦 Found existing Vault container: $EXISTING_VAULT"
    echo "🔗 Will connect broker to existing Vault network"
    
    # Get the network of the existing vault
    VAULT_NETWORK=$(docker inspect "$EXISTING_VAULT" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' | head -1)
    echo "   Network: $VAULT_NETWORK"
    
    # Use the main docker-compose (connects to existing network)
    COMPOSE_FILES="-f docker-compose.yml"
    
else
    echo "🆕 No existing Vault found, will create standalone setup"
    
    # Use override for standalone deployment
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.override.yml"
fi

echo ""
echo "Building and starting services..."
docker-compose $COMPOSE_FILES build broker

echo ""
echo "Starting broker service..."
docker-compose $COMPOSE_FILES up -d broker

echo ""
echo "Waiting for broker to be healthy..."
timeout 60 bash -c 'until docker-compose '$COMPOSE_FILES' ps broker | grep -q "healthy"; do sleep 2; done' || {
    echo "❌ Broker failed to start properly"
    docker-compose $COMPOSE_FILES logs broker
    exit 1
}

echo ""
echo "Setting up Vault configuration..."
docker-compose $COMPOSE_FILES up vault-setup

echo ""
echo "✅ Setup complete!"
echo ""
echo "🔧 Services available:"
echo "   • Broker JWKS: http://localhost:8081/.well-known/jwks.json"
echo "   • Vault UI: http://localhost:8200"
echo ""
echo "🧪 Test authentication:"
echo "   ./scripts/bazel-auth-docker.sh \"//frontend:app\""
echo ""
echo "🛑 To stop services:"
if [[ -n "$EXISTING_VAULT" ]]; then
    echo "   docker-compose down  # (keeps existing Vault running)"
else
    echo "   docker-compose -f docker-compose.yml -f docker-compose.override.yml down"
fi