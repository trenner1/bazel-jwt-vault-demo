import os
import time
import json
from typing import Dict, Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from dotenv import load_dotenv
import httpx

# JOSE (Authlib successor)
from joserfc import jwt
from joserfc.jwk import JWKRegistry
from joserfc.errors import (
    BadSignatureError,
    InvalidHeaderValueError,
    DecodeError,
    InvalidClaimError,
)

load_dotenv()

VAULT_ADDR = os.getenv("VAULT_ADDR", "http://127.0.0.1:8200")
VAULT_TOKEN = os.getenv("VAULT_TOKEN")  # broker’s Vault admin/service token (dev only)
ISSUER = os.getenv("ISSUER", "http://localhost:8080")
AUDIENCE = os.getenv("AUDIENCE", "vault-broker")
KEYSET_PATH = os.getenv("KEYSET_PATH", "jwks.json")
SIGNER_KEYS_PATH = os.getenv("SIGNER_KEYS_PATH", "signer_keys.json")
VAULT_JWT_ROLE = os.getenv("VAULT_JWT_ROLE", "bazel-builds")

app = FastAPI()

# ---- Load JWKS (public) ----
with open(KEYSET_PATH, "r") as f:
    JWKS = json.load(f)
# import as-is (array of JWK dicts); we’ll pick a key by kid per request
JWKS_KEYS = JWKS.get("keys", [])
if not JWKS_KEYS:
    raise RuntimeError("JWKS has no 'keys'")

# ---- Load private JWK for demo signing (dev only) ----
with open(SIGNER_KEYS_PATH, "r") as f:
    SIGNER = json.load(f)
PRIVATE_JWK = JWKRegistry.import_key(SIGNER["private_jwk"])
KID = SIGNER["kid"]


@app.get("/.well-known/jwks.json")
async def jwks():
    """Public JWKS for Vault to validate our demo JWTs (in prod, use real OIDC)."""
    return JSONResponse(JWKS)


def _find_key_by_kid(kid: str):
    for k in JWKS_KEYS:
        if k.get("kid") == kid:
            return JWKRegistry.import_key(k)
    return None


@app.post("/exchange")
async def exchange(req: Request):
    """
    Exchange a caller-signed JWT for a constrained child Vault token.
    Steps:
      1) Verify JWT signature + validate iss/aud/exp/iat.
      2) Vault auth/jwt/login with the JWT (role=bazel-builds).
      3) Create a child token with limited TTL, uses, and rich metadata.
    """
    body = await req.json()
    assertion = body.get("assertion")
    if not assertion:
        raise HTTPException(status_code=400, detail="missing 'assertion'")

    # ---- Verify & validate JWT using joserfc ----
    try:
        # First decode without verification to get the header
        parts = assertion.split('.')
        if len(parts) != 3:
            raise HTTPException(status_code=401, detail="invalid jwt format")
        
        # Decode header to get kid
        import base64
        import json as builtin_json
        
        # Add padding if needed
        header_b64 = parts[0]
        header_b64 += '=' * (4 - len(header_b64) % 4)
        header_bytes = base64.urlsafe_b64decode(header_b64)
        header = builtin_json.loads(header_bytes)
        
        kid = header.get("kid")
        if not kid:
            raise HTTPException(status_code=401, detail="missing kid in header")

        key = _find_key_by_kid(kid)
        if not key:
            raise HTTPException(status_code=401, detail="unknown kid")

        # 1) Decode + verify signature
        token = jwt.decode(assertion, key)

        # 2) Validate claims explicitly (iss/aud/exp/iat)
        # token.claims is a dict-like structure
        claims = token.claims
        now = int(time.time())
        # Minimal manual validation:
        if claims.get("iss") != ISSUER:
            raise InvalidClaimError("iss mismatch")
        aud = claims.get("aud")
        if aud != AUDIENCE and (not isinstance(aud, list) or AUDIENCE not in aud):
            raise InvalidClaimError("aud mismatch")
        exp = int(claims.get("exp", 0))
        iat = int(claims.get("iat", 0))
        if not (iat <= now <= exp):
            raise InvalidClaimError("token not currently valid")

    except (BadSignatureError, InvalidHeaderValueError, DecodeError, InvalidClaimError) as e:
        raise HTTPException(status_code=401, detail=f"jwt invalid: {e}")
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"jwt validation failed: {e}")

    # Extract claims we care about
    groups = claims.get("groups", [])
    repo = claims.get("repo")
    target = claims.get("target")
    run_id = claims.get("run_id")
    if not repo or not target:
        raise HTTPException(status_code=400, detail="repo/target required in claims")

    # ---- Login to Vault via JWT auth role ----
    login_payload = {"role": VAULT_JWT_ROLE, "jwt": assertion}

    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.post(f"{VAULT_ADDR}/v1/auth/jwt/login", json=login_payload)
        if r.status_code != 200:
            raise HTTPException(
                status_code=502,
                detail=f"vault jwt login failed: {r.status_code} {r.text}",
            )
        login = r.json().get("auth", {})
        broker_token = login.get("client_token")
        if not broker_token:
            raise HTTPException(status_code=502, detail="missing broker token from Vault")

        # ---- Create constrained child token with team metadata ----
        team = claims.get("team", "team-default")
        pipeline = claims.get("pipeline", target.replace("/", "_").replace(":", "_"))
        user = claims.get("user", "developer")
        
        meta = {
            "repo": repo,
            "target": target,
            "run_id": str(run_id or "dev"),
            "team": team,
            "pipeline": pipeline,
            "user": user,  # Individual developer for audit
            "groups": ",".join(groups) if isinstance(groups, list) else str(groups),
            "issued_by": "broker",
        }
        tok_req = {
            "no_default_policy": True,
            "policies": ["bazel-team"],  # Team-based policy with templating
            "meta": meta,
            "ttl": "10m",
            "num_uses": 50,
            "renewable": False,
        }
        r2 = await client.post(
            f"{VAULT_ADDR}/v1/auth/token/create",
            headers={"X-Vault-Token": broker_token},
            json=tok_req,
        )
        if r2.status_code != 200:
            raise HTTPException(
                status_code=502,
                detail=f"vault child token create failed: {r2.status_code} {r2.text}",
            )
        child = r2.json().get("auth", {})

    return {"vault_token": child.get("client_token"), "meta": meta}


@app.post("/demo/sign")
async def sign_demo(body: Dict[str, Any]):
    """
    Dev convenience endpoint:
    Mint a short-lived JWT as if the Bazel build signed it.
    In prod, your CI/Bazel flow would sign and call /exchange directly.
    """
    now = int(time.time())
    claims = {
        "iss": ISSUER,
        "aud": AUDIENCE,
        "sub": body.get("team", "team-default"),  # Team identifier (shared within team)
        "exp": now + 180,    # 3 minutes
        "iat": now,
        "groups": body.get("groups", ["bazel-dev"]),
        "repo": body.get("repo", "mono/repo"),
        "target": body.get("target", "//app:build"),
        "run_id": body.get("run_id", f"local-{now}"),
        "user": body.get("user", "developer"),  # Individual developer (for audit)
        "team": body.get("team", "team-default"),  # Team context for policies
        "pipeline": body.get("pipeline", body.get("target", "//app:build").replace("/", "_").replace(":", "_")),
    }

    header = {"alg": "RS256", "kid": KID}
    token = jwt.encode(header, claims, PRIVATE_JWK)
    return {"assertion": token, "claims": claims}
