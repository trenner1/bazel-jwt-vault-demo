# Multi-stage build for Bazel JWT Vault Demo Broker
FROM python:3.13-slim as builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create and activate virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy and install Python dependencies
COPY broker/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r /tmp/requirements.txt

# Production stage
FROM python:3.13-slim as production

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r broker && useradd -r -g broker broker

# Copy virtual environment from builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Set working directory
WORKDIR /app

# Copy broker application and keys
COPY broker/ /app/
RUN chown -R broker:broker /app

# Switch to non-root user
USER broker

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8081/.well-known/jwks.json || exit 1

# Expose port
EXPOSE 8081

# Default environment variables
ENV VAULT_ADDR=http://vault:8200
ENV ISSUER=http://localhost:8080
ENV AUDIENCE=vault-broker

# Start the broker
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8081"]