FROM hashicorp/vault:1.16

# Install curl for network debugging and OIDC endpoint testing
RUN apk add --no-cache curl jq

# Keep the original entrypoint
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["vault", "server", "-dev"]