import json
import secrets
from joserfc.jwk import JWKRegistry

# Generate an RSA private key (2048 bits)
priv = JWKRegistry.generate_key("RSA", 2048, private=True, auto_kid=False)

# Create a kid (keep it stable as long as this key is in use)
kid = secrets.token_urlsafe(8)

# Public JWK with alg/kid
pub = priv.as_dict(private=False)
pub["kid"] = kid
pub["alg"] = "RS256"

# Persist files the broker expects
with open("jwks.json", "w") as f:
    json.dump({"keys": [pub]}, f, indent=2)

with open("signer_keys.json", "w") as f:
    json.dump({"private_jwk": priv.as_dict(), "kid": kid}, f, indent=2)

print("Wrote broker/jwks.json and broker/signer_keys.json (kid =", kid, ")")
