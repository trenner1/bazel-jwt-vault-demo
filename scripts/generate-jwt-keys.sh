#!/bin/bash

# JWT Key Pair Generation Script
# This script generates RSA key pairs for JWT signing and verification

set -e

echo "Generating RSA key pair for JWT signing..."

# Create broker directory if it doesn't exist
mkdir -p broker

# Check if keys already exist
if [[ -f "broker/jwt_signing_key" ]]; then
    echo "WARNING: JWT signing keys already exist!"
    echo "Existing keys found:"
    ls -la broker/jwt_signing_key*
    echo ""
    read -p "Do you want to overwrite the existing keys? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Key generation cancelled. Existing keys preserved."
        exit 0
    fi
    echo "Backing up existing keys..."
    timestamp=$(date +%Y%m%d_%H%M%S)
    cp broker/jwt_signing_key "broker/jwt_signing_key.backup_${timestamp}"
    cp broker/jwt_signing_key.pub "broker/jwt_signing_key.pub.backup_${timestamp}" 2>/dev/null || true
    cp broker/jwt_public_key.pem "broker/jwt_public_key.pem.backup_${timestamp}" 2>/dev/null || true
    echo "Backup created with timestamp: ${timestamp}"
fi

# Generate RSA private key (2048-bit)
echo "   Generating private key..."
openssl genrsa -out broker/jwt_signing_key 2048

# Generate RSA public key
echo "   Generating public key..."
openssl rsa -in broker/jwt_signing_key -pubout -out broker/jwt_signing_key.pub

# Generate PEM format public key (alternative format)
echo "   Generating PEM format public key..."
cp broker/jwt_signing_key.pub broker/jwt_public_key.pem

# Set proper permissions
chmod 600 broker/jwt_signing_key        # Private key - restrict access
chmod 644 broker/jwt_signing_key.pub    # Public key - readable
chmod 644 broker/jwt_public_key.pem     # Public key - readable

echo "RSA key pair generated successfully:"
echo "Private key: broker/jwt_signing_key"
echo "Public key:  broker/jwt_signing_key.pub"
echo "PEM format:  broker/jwt_public_key.pem"
echo ""
echo "The private key is used by the broker to sign JWT tokens"
echo "The public key is used by Vault to verify JWT signatures"
echo ""
echo "Keep the private key secure and never commit it to version control!"