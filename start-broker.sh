#!/bin/bash
# JWT Broker startup script for local development
# SECURITY: Set VAULT_TOKEN environment variable before running
export VAULT_TOKEN=${VAULT_TOKEN:-"<SET_VAULT_TOKEN_ENVIRONMENT_VARIABLE>"}
export VAULT_ADDR="http://127.0.0.1:8200"

# Start the JWT broker
cd broker && python app.py