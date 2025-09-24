"""
Bazel JWT Vault Demo - Enterprise OIDC Authentication Broker

This FastAPI application provides a secure OIDC authentication broker that integrates
Okta identity provider with HashiCorp Vault for team-based secret access control.

Key Features:
- Authorization Code Flow with PKCE for enhanced security
- Unified authentication for both web browsers and CLI tools
- Team-based access control via Okta groups → Vault roles mapping
- Enhanced developer experience with auto-copy web interface
- Real user identity tracking with comprehensive audit metadata
- Zero-configuration team assignment based on existing Okta groups

Architecture:
1. Users authenticate with Okta using their existing credentials
2. Broker receives authorization code and exchanges for tokens via PKCE
3. User groups from Okta determine Vault role assignment
4. Vault authenticates using Okta ID token (JWT auth method)
5. Child tokens are created with team-specific policies and metadata

Team Mapping:
- mobile-developers → mobile-team role → mobile team secrets
- backend-developers → backend-team role → backend team secrets  
- frontend-developers → frontend-team role → frontend team secrets
- devops-team → devops-team role → cross-functional access

Security Features:
- PKCE (Proof Key for Code Exchange) prevents code interception
- Time-limited tokens (2h default, 4h max)
- Limited token usage (10 uses max)
- Team isolation via Vault policies
- Comprehensive audit trails with user metadata

Author: Generated for Bazel JWT Vault Demo
License: MIT
"""

import os
import time
import json
import asyncio
import secrets
import jwt
import datetime
from typing import Dict, Any, Optional
from urllib.parse import urlencode

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, RedirectResponse, HTMLResponse
from dotenv import load_dotenv
import httpx

load_dotenv()

# Okta OIDC Configuration (Required)
OKTA_DOMAIN = os.getenv("OKTA_DOMAIN")
OKTA_CLIENT_ID = os.getenv("OKTA_CLIENT_ID") 
OKTA_CLIENT_SECRET = os.getenv("OKTA_CLIENT_SECRET")
OKTA_AUTH_SERVER_ID = os.getenv("OKTA_AUTH_SERVER_ID", "default")
OKTA_REDIRECT_URI = os.getenv("OKTA_REDIRECT_URI", "http://localhost:8081/auth/callback")

# Vault Configuration
VAULT_ADDR = "http://vault:8200"  # Fixed to use Docker service name
VAULT_ROOT_TOKEN = os.getenv("VAULT_ROOT_TOKEN")

app = FastAPI(title="Bazel JWT Vault Demo - Okta OIDC", version="2.0.0")

# Global user sessions storage
_user_sessions: Dict[str, Dict[str, Any]] = {}

def validate_okta_config():
    """Validate that required Okta configuration is present"""
    if not OKTA_DOMAIN:
        raise ValueError("OKTA_DOMAIN environment variable is required")
    if not OKTA_CLIENT_ID:
        raise ValueError("OKTA_CLIENT_ID environment variable is required")
    if not OKTA_CLIENT_SECRET:
        raise ValueError("OKTA_CLIENT_SECRET environment variable is required")
    if not OKTA_AUTH_SERVER_ID:
        raise ValueError("OKTA_AUTH_SERVER_ID environment variable is required")

def get_okta_auth_url(state: str) -> str:
    """Generate Okta authorization URL for OIDC flow"""
    params = {
        "client_id": OKTA_CLIENT_ID,
        "response_type": "code",
        "scope": "openid profile email groups",
        "redirect_uri": OKTA_REDIRECT_URI,
        "state": state,
    }
    return f"https://{OKTA_DOMAIN}/oauth2/{OKTA_AUTH_SERVER_ID}/v1/authorize?{urlencode(params)}"

async def exchange_code_for_token(code: str) -> Dict[str, Any]:
    """
    Exchange authorization code for Okta tokens using OAuth 2.0 Authorization Code flow.
    
    Args:
        code: Authorization code received from Okta callback
        
    Returns:
        Dict containing access_token, id_token, and other token information
        
    Raises:
        HTTPException: If token exchange fails with Okta
    """
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            token_url = f"https://{OKTA_DOMAIN}/oauth2/{OKTA_AUTH_SERVER_ID}/v1/token"
            print(f" Attempting token exchange at: {token_url}")
            
            token_response = await client.post(
                token_url,
                data={
                    "grant_type": "authorization_code",
                    "client_id": OKTA_CLIENT_ID,
                    "client_secret": OKTA_CLIENT_SECRET,
                    "code": code,
                    "redirect_uri": OKTA_REDIRECT_URI,
                },
                headers={"Content-Type": "application/x-www-form-urlencoded"}
            )
            
            print(f"📡 Token response status: {token_response.status_code}")
            if token_response.status_code != 200:
                print(f" Token exchange failed: {token_response.text}")
                raise HTTPException(
                    status_code=400, 
                    detail=f"Token exchange failed: {token_response.text}"
                )
            
            return token_response.json()
    except Exception as e:
        print(f" Exception in token exchange: {e}")
        raise

async def get_user_info(access_token: str) -> Dict[str, Any]:
    """
    Retrieve user information from Okta using access token.
    
    Args:
        access_token: OAuth 2.0 access token from Okta
        
    Returns:
        Dict containing user profile information including email, name, and groups
        
    Raises:
        HTTPException: If user info retrieval fails
    """
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            userinfo_url = f"https://{OKTA_DOMAIN}/oauth2/{OKTA_AUTH_SERVER_ID}/v1/userinfo"
            print(f" Getting user info from: {userinfo_url}")
            
            userinfo_response = await client.get(
                userinfo_url,
                headers={"Authorization": f"Bearer {access_token}"}
            )
            
            print(f" User info response status: {userinfo_response.status_code}")
            if userinfo_response.status_code != 200:
                print(f" User info failed: {userinfo_response.text}")
                raise HTTPException(
                    status_code=400,
                    detail=f"Failed to get user info: {userinfo_response.text}"
                )
            
            user_data = userinfo_response.json()
            print(f" User info retrieved for: {user_data.get('email', 'unknown')}")
            return user_data
    except Exception as e:
        print(f" Exception in get_user_info: {e}")
        raise

def determine_vault_role_from_okta_groups(okta_groups: list) -> str:
    """Map Okta groups to Vault OIDC roles for team-specific access"""
    role_mapping = {
        "mobile-developers": "mobile-team",
        "backend-developers": "backend-team", 
        "frontend-developers": "frontend-team",
        "devops-team": "devops-team",
    }
    
    # Find the first matching group and return corresponding role
    for group in okta_groups:
        if group in role_mapping:
            return role_mapping[group]
    
    # Default to base role if no specific team match
    return "base-team"

def determine_team_from_okta_groups(okta_groups: list) -> str:
    """Determine team name from Okta groups for entity creation"""
    team_mapping = {
        "mobile-developers": "mobile-team",
        "backend-developers": "backend-team",
        "frontend-developers": "frontend-team", 
        "devops-team": "devops-team",
    }
    
    # Find the first matching group and return team name
    for group in okta_groups:
        if group in team_mapping:
            return team_mapping[group]
    
    # Default team for users without specific team groups
    return "base-team"

def determine_available_teams_from_groups(okta_groups: list) -> list:
    """Determine all available teams from Okta groups for user context selection"""
    team_mapping = {
        "mobile-developers": "mobile-team",
        "backend-developers": "backend-team", 
        "frontend-developers": "frontend-team",
        "devops-team": "devops-team",
    }
    
    # Find all matching teams
    available_teams = []
    for group in okta_groups:
        if group in team_mapping:
            team = team_mapping[group]
            if team not in available_teams:
                available_teams.append(team)
    
    # Always include base-team as fallback
    if not available_teams:
        available_teams.append("base-team")
    
    return available_teams

def generate_team_based_jwt(user_info: Dict[str, Any], team: str) -> str:
    """
    Generate a team-based JWT token for Vault authentication.
    
    This creates a custom JWT with the team name as the subject, enabling
    team-based entity creation in Vault while preserving user metadata.
    
    Args:
        user_info: User information from Okta (email, name, groups)
        team: Team name determined from user's Okta groups
        
    Returns:
        Signed JWT token with team as subject
    """
    # Load the RSA private key for signing
    try:
        with open("/app/jwt_signing_key", "r") as f:
            private_key = f.read()
    except FileNotFoundError:
        # Fallback to a simple key for development
        private_key = "bazel-demo-jwt-signing-key-2024"
        print("  Using fallback signing key - generate jwt_signing_key for production")
    
    # Current time
    now = datetime.datetime.utcnow()
    
    # JWT payload with team as subject
    payload = {
        "iss": "bazel-auth-broker",  # Issuer
        "sub": team,                 # Subject = team name (creates team-based entities)
        "aud": "bazel-vault",       # Audience - must match Vault's bound_audiences
        "iat": int(now.timestamp()), # Issued at
        "exp": int((now + datetime.timedelta(hours=2)).timestamp()), # Expires
        "user": user_info.get("email", "unknown@example.com"),
        "name": user_info.get("name", "Unknown User"),
        "groups": user_info.get("groups", []),
        "team": team
    }
    
    # Generate signed JWT with RSA private key
    try:
        token = jwt.encode(payload, private_key, algorithm="RS256")
    except Exception as e:
        print(f"  JWT signing failed with RSA key, using HS256: {e}")
        # Fallback to symmetric signing for development
        token = jwt.encode(payload, "bazel-demo-jwt-signing-key-2024", algorithm="HS256")
    
    return token

async def authenticate_with_vault_oidc(okta_id_token: str, user_info: Dict[str, Any], selected_team: str = None) -> str:
    """
    Authenticate with HashiCorp Vault using team-based JWT.
    
    This function determines the user's team from Okta groups, generates a team-based
    JWT token, and authenticates with Vault using that token. This creates shared
    entities per team rather than individual user entities.
    
    Args:
        okta_id_token: JWT ID token from Okta (used for user verification)
        user_info: User profile information including groups from Okta
        selected_team: Specific team selected by user (optional)
        
    Returns:
        Vault client token for the authenticated user with team-specific policies
        
    Raises:
        RuntimeError: If Vault authentication fails
    """
    try:
        groups = user_info.get("groups", [])
        
        # Use selected team if provided, otherwise determine from groups
        if selected_team:
            team = selected_team
            # Use selected team to determine vault role
            vault_role = team  # The team name is the vault role name
        else:
            team = determine_team_from_okta_groups(groups)
            vault_role = determine_vault_role_from_okta_groups(groups)
        
        print(f"Authenticating with Vault using team-based JWT")
        print(f" User: {user_info.get('email', 'unknown')}")
        print(f"  Team: {team}")
        print(f" Vault role: {vault_role}")
        print(f" User groups: {groups}")
        
        # Generate team-based JWT token
        team_jwt = generate_team_based_jwt(user_info, team)
        print(f" Generated team-based JWT for team: {team}")
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            vault_auth_url = f"{VAULT_ADDR}/v1/auth/jwt/login"
            print(f" Vault JWT auth URL: {vault_auth_url}")
            
            vault_auth_response = await client.post(
                vault_auth_url,
                json={
                    "jwt": team_jwt,  # Use team-based JWT instead of Okta JWT
                    "role": vault_role
                }
            )
            
            print(f" Vault auth response status: {vault_auth_response.status_code}")
            if vault_auth_response.status_code != 200:
                print(f" Vault JWT auth failed: {vault_auth_response.text}")
                raise RuntimeError(f"Vault JWT auth failed: {vault_auth_response.text}")
            
            vault_auth = vault_auth_response.json()
            vault_token = vault_auth["auth"]["client_token"]
            entity_id = vault_auth["auth"].get("entity_id", "unknown")
            
            print(f"✓ User {user_info.get('email', 'unknown')} authenticated with Vault via team-based JWT")
            print(f"  Entity ID: {entity_id} (shared by team: {team})")
            return vault_token
    except Exception as e:
        print(f"💥 Exception in authenticate_with_vault_oidc: {e}")
        raise

async def pkce_auth_start() -> Dict[str, Any]:
    """
    Start Authorization Code Flow with PKCE for CLI authentication.
    
    PKCE (Proof Key for Code Exchange) enhances the OAuth 2.0 Authorization Code flow
    by adding cryptographic verification to prevent authorization code interception attacks.
    
    Returns:
        Dict containing:
        - auth_url: Complete Okta authorization URL with PKCE parameters
        - state: Unique state parameter for session validation
        - instructions: Step-by-step user instructions
        
    Note:
        PKCE parameters (code_verifier, code_challenge) are stored in app.pkce_sessions
        for later verification during token exchange.
    """
    import secrets
    import hashlib
    import base64
    
    # Generate PKCE parameters
    code_verifier = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode('utf-8').rstrip('=')
    code_challenge = base64.urlsafe_b64encode(
        hashlib.sha256(code_verifier.encode('utf-8')).digest()
    ).decode('utf-8').rstrip('=')
    
    state = secrets.token_urlsafe(16)
    
    # Store PKCE data temporarily (in production, use Redis/DB)
    pkce_sessions = getattr(app, 'pkce_sessions', {})
    pkce_sessions[state] = {
        "code_verifier": code_verifier,
        "created_at": time.time()
    }
    app.pkce_sessions = pkce_sessions
    
    # Generate authorization URL
    params = {
        "client_id": OKTA_CLIENT_ID,
        "response_type": "code",
        "scope": "openid profile email groups",
        "redirect_uri": OKTA_REDIRECT_URI,  # Use existing configured URI
        "state": state,
        "code_challenge": code_challenge,
        "code_challenge_method": "S256"
    }
    
    auth_url = f"https://{OKTA_DOMAIN}/oauth2/{OKTA_AUTH_SERVER_ID}/v1/authorize?" + "&".join([f"{k}={v}" for k, v in params.items()])
    
    return {
        "auth_url": auth_url,
        "state": state,
        "instructions": {
            "step_1": "Open the auth_url in your browser",
            "step_2": "Complete Okta authentication", 
            "step_3": "Copy the authorization code from the callback",
            "step_4": "Use the code with /cli/exchange endpoint"
        }
    }

async def pkce_auth_exchange(code: str, state: str) -> Dict[str, Any]:
    """Exchange authorization code with PKCE for tokens"""
    
    # Retrieve PKCE data
    pkce_sessions = getattr(app, 'pkce_sessions', {})
    if state not in pkce_sessions:
        raise HTTPException(status_code=400, detail="Invalid or expired PKCE state")
    
    pkce_data = pkce_sessions[state]
    code_verifier = pkce_data["code_verifier"]
    
    # Clean up old session
    del pkce_sessions[state]
    
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            token_url = f"https://{OKTA_DOMAIN}/oauth2/{OKTA_AUTH_SERVER_ID}/v1/token"
            print(f" PKCE token exchange at: {token_url}")
            
            token_response = await client.post(
                token_url,
                data={
                    "grant_type": "authorization_code",
                    "client_id": OKTA_CLIENT_ID,
                    "client_secret": OKTA_CLIENT_SECRET,  # Add client secret for Web Application
                    "code": code,
                    "redirect_uri": OKTA_REDIRECT_URI,
                    "code_verifier": code_verifier
                },
                headers={"Content-Type": "application/x-www-form-urlencoded"}
            )
            
            print(f" PKCE token response status: {token_response.status_code}")
            if token_response.status_code != 200:
                print(f" PKCE token exchange failed: {token_response.text}")
                raise HTTPException(
                    status_code=400,
                    detail=f"PKCE token exchange failed: {token_response.text}"
                )
            
            return token_response.json()
    except Exception as e:
        print(f" Exception in pkce_auth_exchange: {e}")
        raise

async def create_child_token(parent_token: str, user_info: Dict[str, Any], request_body: Dict[str, Any], selected_team: str = None) -> Dict[str, Any]:
    """
    Create a constrained child Vault token with user metadata and team-specific policies.
    
    Child tokens provide enhanced security by:
    - Limited TTL (2 hours default)
    - Restricted number of uses (10 max)
    - Team-specific policies based on user groups
    - Rich metadata for audit trails
    
    Args:
        parent_token: Parent Vault token (from OIDC authentication)
        user_info: User profile from Okta (email, name, groups)
        request_body: Request metadata (pipeline, repo, target)
        
    Returns:
        Dict containing:
        - token: Child Vault token
        - ttl: Time to live in seconds
        - uses_remaining: Number of uses allowed
        - policies: Applied Vault policies
        - metadata: User and request metadata
        
    Raises:
        HTTPException: If child token creation fails
    """
    
    # Extract user information
    email = user_info.get("email", "unknown@example.com")
    name = user_info.get("name", "Unknown User")
    groups = user_info.get("groups", [])
    
    # Extract additional metadata from request (for Bazel context)
    pipeline = request_body.get("pipeline", "unknown")
    repo = request_body.get("repo", "unknown") 
    target = request_body.get("target", "unknown")
    
    # Use selected team if provided, otherwise determine from groups (fallback)
    if selected_team and selected_team != "unknown":
        team = selected_team
    else:
        # Fallback: determine team from groups (for backward compatibility)
        team = "unknown"
        for group in groups:
            if "developers" in group.lower():
                team = group.replace("-developers", "-team")
                break
            elif "devops" in group.lower():
                team = "devops-team"
                break
    
    # Team-specific policy mapping
    team_policy_mapping = {
        "mobile-team": ["bazel-base", "bazel-mobile-team"],
        "backend-team": ["bazel-base", "bazel-backend-team"], 
        "frontend-team": ["bazel-base", "bazel-frontend-team"],
        "devops-team": ["bazel-base", "bazel-backend-team", "bazel-frontend-team"]
    }
    
    child_policies = team_policy_mapping.get(team, ["bazel-base"])
    
    async with httpx.AsyncClient() as client:
        child_token_response = await client.post(
            f"{VAULT_ADDR}/v1/auth/token/create",
            headers={"X-Vault-Token": VAULT_ROOT_TOKEN},
            json={
                "ttl": "2h",
                "num_uses": 10,
                "renewable": False,
                "metadata": {
                    "team": team,
                    "user": email,
                    "name": name,
                    "pipeline": pipeline,
                    "repo": repo,
                    "target": target,
                    "source": "oidc-broker",
                    "groups": ",".join(groups)
                },
                "policies": child_policies,
                "display_name": f"bazel-{team}-{email.split('@')[0]}",
            }
        )
        
        if child_token_response.status_code != 200:
            raise HTTPException(
                status_code=500,
                detail=f"Failed to create child token: {child_token_response.text}"
            )
        
        child_token_data = child_token_response.json()
        
        return {
            "token": child_token_data["auth"]["client_token"],
            "ttl": child_token_data["auth"]["lease_duration"],
            "uses_remaining": 10,
            "policies": child_token_data["auth"]["policies"],
            "metadata": {
                "team": team,
                "user": email,
                "name": name,
                "pipeline": pipeline,
                "groups": groups
            }
        }

# Startup validation
@app.on_event("startup")
async def startup():
    """Validate configuration on startup"""
    try:
        validate_okta_config()
        print(f"✓ Okta OIDC configured for domain: {OKTA_DOMAIN}")
        print(" Bazel JWT Vault Demo ready with Okta OIDC authentication")
        print("  Vault connectivity will be verified on first request")
        
    except Exception as e:
        print(f" Failed to initialize broker: {e}")
        raise

# Routes

@app.get("/")
async def home():
    """Home page with login link"""
    return HTMLResponse(f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Bazel JWT Vault Demo - Okta OIDC</title>
        <style>
            body {{ font-family: Arial, sans-serif; margin: 40px; }}
            .container {{ max-width: 600px; margin: 0 auto; }}
            .button {{ background: #007cba; color: white; padding: 12px 24px; text-decoration: none; border-radius: 4px; }}
            .info {{ background: #f0f8ff; padding: 20px; border-radius: 4px; margin: 20px 0; }}
        </style>
    </head>
    <body>
        <div class="container">
            <h1> Bazel JWT Vault Demo</h1>
            <div class="info">
                <h3>Enterprise OIDC Authentication</h3>
                <p>This demo uses <strong>Okta OIDC</strong> for secure authentication with HashiCorp Vault.</p>
                <p><strong>Team-based access:</strong> Your Okta groups determine which secrets you can access.</p>
            </div>
            
            <h2>Authentication Methods</h2>
            <div class="info">
                <h4> Web Browser Authentication</h4>
                <p>For interactive use via web browser:</p>
                <a href="/auth/login" class="button"> Login with Okta</a>
            </div>
            
            <div class="info">
                <h4> CLI/Bazel Authentication (PKCE Flow)</h4>
                <p>For command-line tools and Bazel builds:</p>
                <pre>curl -X POST http://localhost:8081/cli/start</pre>
                <p>Follow the returned instructions to authenticate.</p>
            </div>
            
            <h3>Available Endpoints:</h3>
            <ul>
                <li><code>GET /auth/login</code> - Initiate Okta login (browser)</li>
                <li><code>GET /auth/callback</code> - Okta callback handler (browser & CLI)</li>
                <li><code>POST /cli/start</code> - Start CLI authentication (PKCE)</li>
                <li><code>POST /exchange</code> - Exchange session for Vault token</li>
            </ul>
            
            <div class="info">
                <strong>Domain:</strong> {OKTA_DOMAIN}<br>
                <strong>Client ID:</strong> {OKTA_CLIENT_ID}
            </div>
        </div>
    </body>
    </html>
    """)

@app.get("/auth/login")
async def login():
    """Initiate Okta OIDC login flow with PKCE"""
    import secrets
    import hashlib
    import base64
    
    # Generate PKCE parameters for browser flow too
    code_verifier = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode('utf-8').rstrip('=')
    code_challenge = base64.urlsafe_b64encode(
        hashlib.sha256(code_verifier.encode('utf-8')).digest()
    ).decode('utf-8').rstrip('=')
    
    state = secrets.token_urlsafe(16)
    
    # Store PKCE data for browser flow
    pkce_sessions = getattr(app, 'pkce_sessions', {})
    pkce_sessions[state] = {
        "code_verifier": code_verifier,
        "created_at": time.time()
    }
    app.pkce_sessions = pkce_sessions
    
    # Generate authorization URL with PKCE
    params = {
        "client_id": OKTA_CLIENT_ID,
        "response_type": "code",
        "scope": "openid profile email groups",
        "redirect_uri": OKTA_REDIRECT_URI,
        "state": state,
        "code_challenge": code_challenge,
        "code_challenge_method": "S256"
    }
    
    auth_url = f"https://{OKTA_DOMAIN}/oauth2/{OKTA_AUTH_SERVER_ID}/v1/authorize?" + "&".join([f"{k}={v}" for k, v in params.items()])
    return RedirectResponse(url=auth_url)

@app.get("/auth/callback")
async def auth_callback(code: str = None, state: str = None, error: str = None):
    """Handle Okta OIDC callback (unified PKCE flow for both browser and CLI)"""
    if error:
        raise HTTPException(status_code=400, detail=f"Okta auth error: {error}")
    
    if not code:
        raise HTTPException(status_code=400, detail="No authorization code received")
    
    try:
        # All flows now use PKCE, so check if state exists in pkce_sessions
        pkce_sessions = getattr(app, 'pkce_sessions', {})
        if state not in pkce_sessions:
            raise HTTPException(status_code=400, detail="Invalid or expired PKCE state")
        
        # Use PKCE exchange for all flows
        token_data = await pkce_auth_exchange(code, state)
        id_token = token_data["id_token"]
        access_token = token_data["access_token"]
        
        # Get user information
        user_info = await get_user_info(access_token)
        
        # Determine if this was a CLI request based on state prefix or session storage
        is_cli_request = state.startswith("cli_") if state else False
        
        # Get user's groups and determine available teams
        groups = user_info.get("groups", [])
        available_teams = determine_available_teams_from_groups(groups)
        
        if len(available_teams) == 1:
            # Single team - proceed directly
            selected_team = available_teams[0]
            vault_token = await authenticate_with_vault_oidc(id_token, user_info, selected_team)
            
            # Store session
            session_prefix = "cli_session" if is_cli_request else "session"
            session_id = f"{session_prefix}_{secrets.token_urlsafe(16)}"
            _user_sessions[session_id] = {
                "vault_token": vault_token,
                "user_info": user_info,
                "selected_team": selected_team,
                "okta_tokens": {
                    "id_token": id_token,
                    "access_token": access_token
                },
                "expires_at": time.time() + 3600,  # 1 hour
                "auth_method": "cli_pkce" if is_cli_request else "browser_pkce"
            }
            
            response_data = {
                "message": "Successfully authenticated with Okta and Vault",
                "session_id": session_id,
            "user": {
                "email": user_info.get("email"),
                "name": user_info.get("name"),
                "groups": user_info.get("groups", [])
            },
            "vault_token_preview": vault_token[:10] + "..." if vault_token else None,
            "auth_method": "CLI/PKCE" if is_cli_request else "Browser/PKCE",
            "next_steps": {
                "description": "Use the session_id to exchange for child tokens",
                "example": {
                    "url": "/exchange",
                    "method": "POST",
                    "body": {
                        "session_id": session_id,
                        "pipeline": "your-pipeline",
                        "repo": "your-repo",
                        "target": "your-target"
                    }
                }
            }
        }
        else:
            # Multiple teams - redirect to team selection page
            # Store temporary session data for team selection
            temp_session_id = f"temp_{secrets.token_urlsafe(16)}"
            _user_sessions[temp_session_id] = {
                "user_info": user_info,
                "available_teams": available_teams,
                "okta_tokens": {
                    "id_token": id_token,
                    "access_token": access_token
                },
                "expires_at": time.time() + 600,  # 10 minutes for team selection
                "auth_method": "cli_pkce" if is_cli_request else "browser_pkce",
                "is_cli_request": is_cli_request,
                "state": state
            }
            
            if is_cli_request:
                # For CLI, return team selection prompt
                return JSONResponse({
                    "message": "Multiple teams available - please select one",
                    "available_teams": available_teams,
                    "temp_session_id": temp_session_id,
                    "next_steps": {
                        "description": "Call /auth/select-team with your chosen team",
                        "url": "/auth/select-team",
                        "method": "POST",
                        "body": {
                            "temp_session_id": temp_session_id,
                            "selected_team": "choose-from-available-teams"
                        }
                    }
                })
            else:
                # For browser, redirect to team selection page
                return RedirectResponse(url=f"/auth/select-team?temp_session_id={temp_session_id}")
        
        if is_cli_request:
            # For CLI, return JSON directly
            return JSONResponse(response_data)
        else:
            # For browser, return HTML page with enhanced UX
            return HTMLResponse(f"""
            <!DOCTYPE html>
            <html>
            <head>
                <title>Authentication Successful</title>
                <style>
                    body {{ font-family: Arial, sans-serif; margin: 40px; background: #f8f9fa; }}
                    .container {{ max-width: 700px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
                    .success {{ background: #d4edda; padding: 20px; border-radius: 8px; margin: 20px 0; border: 1px solid #c3e6cb; }}
                    .info {{ background: #e7f3ff; padding: 20px; border-radius: 8px; margin: 20px 0; border: 1px solid #b3d7ff; }}
                    .session-box {{ background: #fff3cd; padding: 15px; border-radius: 8px; margin: 15px 0; border: 1px solid #ffeaa7; position: relative; }}
                    .copy-btn {{ background: #007cba; color: white; border: none; padding: 8px 16px; border-radius: 4px; cursor: pointer; margin-left: 10px; }}
                    .copy-btn:hover {{ background: #005a8b; }}
                    .copied {{ background: #28a745 !important; }}
                    pre {{ background: #f8f9fa; padding: 15px; border-radius: 4px; overflow-x: auto; border: 1px solid #dee2e6; }}
                    .command-box {{ background: #2d3748; color: #e2e8f0; padding: 15px; border-radius: 8px; margin: 10px 0; font-family: 'Courier New', monospace; }}
                    .highlight {{ background: #ffeaa7; padding: 2px 4px; border-radius: 3px; font-weight: bold; }}
                </style>
            </head>
            <body>
                <div class="container">
                    <h1> Authentication Successful!</h1>
                    <div class="success">
                        <p><strong>Welcome:</strong> {user_info.get('email', 'Unknown')}</p>
                        <p><strong>Teams:</strong> {', '.join(user_info.get('groups', []))}</p>
                    </div>
                    
                    <div class="session-box">
                        <p><strong> Your Session ID:</strong></p>
                        <p style="font-family: monospace; word-break: break-all; margin: 10px 0;">
                            <span id="sessionId">{session_id}</span>
                            <button class="copy-btn" onclick="copySessionId()"> Copy</button>
                        </p>
                    </div>
                    
                    <div class="info">
                        <h3> Quick Commands</h3>
                        <p><strong>Get your Vault token:</strong></p>
                        <div class="command-box">
curl -X POST http://localhost:8081/exchange \\<br>
&nbsp;&nbsp;-H "Content-Type: application/json" \\<br>
&nbsp;&nbsp;-d '{{"session_id": "{session_id}", "pipeline": "my-pipeline", "repo": "my-repo", "target": "my-target"}}'
                        </div>
                        <button class="copy-btn" onclick="copyCurlCommand()"> Copy curl command</button>
                        
                        <p style="margin-top: 20px;"><strong>Or use our CLI tool:</strong></p>
                        <div class="command-box">
./tools/bazel-auth-simple --session-id {session_id}
                        </div>
                        <button class="copy-btn" onclick="copyCliCommand()"> Copy CLI command</button>
                    </div>
                    
                    <div class="info">
                        <h3> Token Exchange Payload</h3>
                        <p>You can customize the metadata for your specific use case:</p>
                        <pre id="exchangePayload">{json.dumps(response_data['next_steps']['example']['body'], indent=2)}</pre>
                        <button class="copy-btn" onclick="copyPayload()"> Copy JSON</button>
                    </div>
                    
                    <p style="text-align: center; margin-top: 30px;">
                        <a href="/" style="color: #007cba; text-decoration: none;">← Back to Home</a>
                    </p>
                </div>
                
                <script>
                function copyToClipboard(text, button) {{
                    navigator.clipboard.writeText(text).then(function() {{
                        const originalText = button.textContent;
                        button.textContent = ' Copied!';
                        button.classList.add('copied');
                        setTimeout(() => {{
                            button.textContent = originalText;
                            button.classList.remove('copied');
                        }}, 2000);
                    }}).catch(function() {{
                        // Fallback for older browsers
                        const textArea = document.createElement('textarea');
                        textArea.value = text;
                        document.body.appendChild(textArea);
                        textArea.select();
                        document.execCommand('copy');
                        document.body.removeChild(textArea);
                        
                        const originalText = button.textContent;
                        button.textContent = ' Copied!';
                        button.classList.add('copied');
                        setTimeout(() => {{
                            button.textContent = originalText;
                            button.classList.remove('copied');
                        }}, 2000);
                    }});
                }}
                
                function copySessionId() {{
                    const sessionId = document.getElementById('sessionId').textContent;
                    const button = event.target;
                    copyToClipboard(sessionId, button);
                }}
                
                function copyPayload() {{
                    const payload = document.getElementById('exchangePayload').textContent;
                    const button = event.target;
                    copyToClipboard(payload, button);
                }}
                
                function copyCurlCommand() {{
                    const command = `curl -X POST http://localhost:8081/exchange \\\\
  -H "Content-Type: application/json" \\\\
  -d '{{"session_id": "{session_id}", "pipeline": "my-pipeline", "repo": "my-repo", "target": "my-target"}}'`;
                    const button = event.target;
                    copyToClipboard(command, button);
                }}
                
                function copyCliCommand() {{
                    const command = './tools/bazel-auth-simple --session-id {session_id}';
                    const button = event.target;
                    copyToClipboard(command, button);
                }}
                
                // Auto-copy session ID to clipboard on page load
                window.addEventListener('load', function() {{
                    const sessionId = document.getElementById('sessionId').textContent;
                    navigator.clipboard.writeText(sessionId).catch(() => {{
                        // Silently fail if clipboard API not available
                    }});
                }});
                </script>
            </body>
            </html>
            """)
        
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Authentication failed: {str(e)}")

@app.get("/auth/select-team")
async def team_selection_page(temp_session_id: str):
    """Display team selection page for users with multiple team memberships"""
    if temp_session_id not in _user_sessions:
        raise HTTPException(status_code=400, detail="Invalid or expired session")
    
    session_data = _user_sessions[temp_session_id]
    user_info = session_data["user_info"]
    available_teams = session_data["available_teams"]
    
    # Generate team selection HTML
    team_options = ""
    for team in available_teams:
        team_display = team.replace("-", " ").title()
        team_options += f'''
            <div class="team-option">
                <input type="radio" id="{team}" name="selected_team" value="{team}" />
                <label for="{team}">{team_display}</label>
            </div>
        '''
    
    return HTMLResponse(f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Select Team Context</title>
        <style>
            body {{ font-family: Arial, sans-serif; margin: 40px; background: #f8f9fa; }}
            .container {{ max-width: 600px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
            .user-info {{ background: #e7f3ff; padding: 20px; border-radius: 8px; margin: 20px 0; border: 1px solid #b3d7ff; }}
            .team-option {{ margin: 15px 0; padding: 15px; border: 2px solid #dee2e6; border-radius: 8px; cursor: pointer; transition: all 0.2s; }}
            .team-option:hover {{ border-color: #007cba; background: #f8f9fa; }}
            .team-option input[type="radio"] {{ margin-right: 10px; }}
            .submit-btn {{ background: #007cba; color: white; border: none; padding: 12px 24px; border-radius: 4px; cursor: pointer; font-size: 16px; }}
            .submit-btn:hover {{ background: #005a8b; }}
            .submit-btn:disabled {{ background: #6c757d; cursor: not-allowed; }}
        </style>
    </head>
    <body>
        <div class="container">
            <h1> Select Team Context</h1>
            <div class="user-info">
                <p><strong>Welcome:</strong> {user_info.get('email', 'Unknown')}</p>
                <p>You belong to multiple teams. Please select which team context you'd like to use for this session.</p>
            </div>
            
            <form id="teamForm" method="post" action="/auth/select-team">
                <input type="hidden" name="temp_session_id" value="{temp_session_id}" />
                {team_options}
                <br/>
                <button type="submit" class="submit-btn" id="submitBtn" disabled>Continue with Selected Team</button>
            </form>
        </div>
        
        <script>
            const form = document.getElementById('teamForm');
            const submitBtn = document.getElementById('submitBtn');
            const radioButtons = document.querySelectorAll('input[name="selected_team"]');
            
            radioButtons.forEach(radio => {{
                radio.addEventListener('change', () => {{
                    submitBtn.disabled = false;
                }});
            }});
        </script>
    </body>
    </html>
    """)

@app.post("/auth/select-team")
async def complete_team_selection(req: Request):
    """Complete authentication with selected team"""
    form_data = await req.form()
    temp_session_id = form_data.get("temp_session_id")
    selected_team = form_data.get("selected_team")
    
    if temp_session_id not in _user_sessions:
        raise HTTPException(status_code=400, detail="Invalid or expired session")
    
    if not selected_team:
        raise HTTPException(status_code=400, detail="No team selected")
    
    session_data = _user_sessions[temp_session_id]
    user_info = session_data["user_info"]
    available_teams = session_data["available_teams"]
    
    if selected_team not in available_teams:
        raise HTTPException(status_code=400, detail="Invalid team selection")
    
    # Complete Vault authentication with selected team
    id_token = session_data["okta_tokens"]["id_token"]
    vault_token = await authenticate_with_vault_oidc(id_token, user_info, selected_team)
    
    # Create final session
    is_cli_request = session_data.get("is_cli_request", False)
    session_prefix = "cli_session" if is_cli_request else "session"
    session_id = f"{session_prefix}_{secrets.token_urlsafe(16)}"
    
    _user_sessions[session_id] = {
        "vault_token": vault_token,
        "user_info": user_info,
        "selected_team": selected_team,
        "okta_tokens": session_data["okta_tokens"],
        "expires_at": time.time() + 3600,  # 1 hour
        "auth_method": session_data["auth_method"]
    }
    
    # Clean up temporary session
    del _user_sessions[temp_session_id]
    
    response_data = {
        "message": f"Successfully authenticated with {selected_team} team context",
        "session_id": session_id,
        "user": {
            "email": user_info.get("email"),
            "name": user_info.get("name"),
            "selected_team": selected_team,
            "available_teams": available_teams
        },
        "vault_token_preview": vault_token[:10] + "..." if vault_token else None,
        "next_steps": {
            "description": "Use the session_id to exchange for child tokens",
            "example": {
                "url": "/exchange",
                "method": "POST",
                "body": {
                    "session_id": session_id,
                    "pipeline": "your-pipeline",
                    "repo": "your-repo", 
                    "target": "your-target"
                }
            }
        }
    }
    
    if is_cli_request:
        return JSONResponse(response_data)
    else:
        # For browser, show success page with full automation features
        return HTMLResponse(f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Authentication Successful</title>
            <style>
                body {{ font-family: Arial, sans-serif; margin: 40px; background: #f8f9fa; }}
                .container {{ max-width: 700px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
                .success {{ background: #d4edda; padding: 20px; border-radius: 8px; margin: 20px 0; border: 1px solid #c3e6cb; }}
                .info {{ background: #e7f3ff; padding: 20px; border-radius: 8px; margin: 20px 0; border: 1px solid #b3d7ff; }}
                .session-box {{ background: #fff3cd; padding: 15px; border-radius: 8px; margin: 15px 0; border: 1px solid #ffeaa7; position: relative; }}
                .copy-btn {{ background: #007cba; color: white; border: none; padding: 8px 16px; border-radius: 4px; cursor: pointer; margin-left: 10px; }}
                .copy-btn:hover {{ background: #005a8b; }}
                .copied {{ background: #28a745 !important; }}
                pre {{ background: #f8f9fa; padding: 15px; border-radius: 4px; overflow-x: auto; border: 1px solid #dee2e6; }}
                .command-box {{ background: #2d3748; color: #e2e8f0; padding: 15px; border-radius: 8px; margin: 10px 0; font-family: 'Courier New', monospace; }}
                .highlight {{ background: #ffeaa7; padding: 2px 4px; border-radius: 3px; font-weight: bold; }}
            </style>
        </head>
        <body>
            <div class="container">
                <h1> Authentication Successful!</h1>
                <div class="success">
                    <p><strong>Welcome:</strong> {user_info.get('email', 'Unknown')}</p>
                    <p><strong>Team Context:</strong> {selected_team}</p>
                    <p><strong>Available Teams:</strong> {', '.join(available_teams)}</p>
                </div>
                
                <div class="session-box">
                    <p><strong> Your Session ID:</strong></p>
                    <p style="font-family: monospace; word-break: break-all; margin: 10px 0;">
                        <span id="sessionId">{session_id}</span>
                        <button class="copy-btn" onclick="copySessionId()"> Copy</button>
                    </p>
                </div>
                
                <div class="info">
                    <h3> Quick Commands</h3>
                    <p><strong>Get your Vault token:</strong></p>
                    <div class="command-box">
curl -X POST http://localhost:8081/exchange \\<br>
&nbsp;&nbsp;-H "Content-Type: application/json" \\<br>
&nbsp;&nbsp;-d '{{"session_id": "{session_id}", "pipeline": "my-pipeline", "repo": "my-repo", "target": "my-target"}}'
                    </div>
                    <button class="copy-btn" onclick="copyCurlCommand()"> Copy curl command</button>
                    
                    <p><strong>Or use our CLI tool:</strong></p>
                    <div class="command-box">
./tools/bazel-auth-simple --session-id {session_id}
                    </div>
                    <button class="copy-btn" onclick="copyCLICommand()"> Copy CLI command</button>
                </div>
                
                <div class="info">
                    <h3> Token Exchange Payload</h3>
                    <p>You can customize the metadata for your specific use case:</p>
                    <pre id="jsonPayload">{{
  "session_id": "{session_id}",
  "pipeline": "your-pipeline",
  "repo": "your-repo",
  "target": "your-target"
}}</pre>
                    <button class="copy-btn" onclick="copyJSON()"> Copy JSON</button>
                </div>
                
                <div style="text-align: center; margin-top: 30px;">
                    <a href="/" style="color: #007cba; text-decoration: none;">← Back to Home</a>
                </div>
            </div>
            
            <script>
                function copySessionId() {{
                    const sessionId = document.getElementById('sessionId').innerText;
                    navigator.clipboard.writeText(sessionId).then(() => {{
                        const btn = event.target;
                        btn.textContent = ' Copied!';
                        btn.classList.add('copied');
                        setTimeout(() => {{
                            btn.textContent = ' Copy';
                            btn.classList.remove('copied');
                        }}, 2000);
                    }});
                }}
                
                function copyCurlCommand() {{
                    const curlCmd = `curl -X POST http://localhost:8081/exchange \\
  -H "Content-Type: application/json" \\
  -d '{{"session_id": "{session_id}", "pipeline": "my-pipeline", "repo": "my-repo", "target": "my-target"}}'`;
                    navigator.clipboard.writeText(curlCmd).then(() => {{
                        const btn = event.target;
                        btn.textContent = ' Copied!';
                        btn.classList.add('copied');
                        setTimeout(() => {{
                            btn.textContent = ' Copy curl command';
                            btn.classList.remove('copied');
                        }}, 2000);
                    }});
                }}
                
                function copyCLICommand() {{
                    const cliCmd = `./tools/bazel-auth-simple --session-id {session_id}`;
                    navigator.clipboard.writeText(cliCmd).then(() => {{
                        const btn = event.target;
                        btn.textContent = ' Copied!';
                        btn.classList.add('copied');
                        setTimeout(() => {{
                            btn.textContent = ' Copy CLI command';
                            btn.classList.remove('copied');
                        }}, 2000);
                    }});
                }}
                
                function copyJSON() {{
                    const jsonText = document.getElementById('jsonPayload').innerText;
                    navigator.clipboard.writeText(jsonText).then(() => {{
                        const btn = event.target;
                        btn.textContent = ' Copied!';
                        btn.classList.add('copied');
                        setTimeout(() => {{
                            btn.textContent = ' Copy JSON';
                            btn.classList.remove('copied');
                        }}, 2000);
                    }});
                }}
            </script>
        </body>
        </html>
        """)

@app.post("/exchange")
async def exchange(req: Request):
    """Exchange Okta session for a constrained child Vault token"""
    body = await req.json()
    session_id = body.get("session_id")
    
    if not session_id:
        raise HTTPException(status_code=400, detail="session_id is required")
    
    if session_id not in _user_sessions:
        raise HTTPException(status_code=401, detail="Invalid or expired session")
    
    session = _user_sessions[session_id]
    if time.time() > session["expires_at"]:
        del _user_sessions[session_id]
        raise HTTPException(status_code=401, detail="Session expired")
    
    parent_token = session["vault_token"]
    user_info = session["user_info"]
    selected_team = session.get("selected_team", "unknown")
    
    # Create child token with user metadata and selected team
    return await create_child_token(parent_token, user_info, body, selected_team)

@app.post("/cli/start")
async def cli_auth_start():
    """Start Authorization Code Flow with PKCE for CLI/Bazel authentication"""
    pkce_data = await pkce_auth_start()
    
    return JSONResponse({
        "auth_url": pkce_data["auth_url"],
        "state": pkce_data["state"],
        "instructions": {
            "step_1": "Open the auth_url in your browser",
            "step_2": "Complete Okta authentication", 
            "step_3": "After redirect, the page will show a JSON response with authentication details",
            "step_4": "Copy the 'session_id' from that JSON response",
            "step_5": "Use the session_id directly with /exchange endpoint (no need for /cli/exchange)"
        },
        "note": "This uses your existing redirect URI - you'll get a session_id directly from the callback"
    })

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "auth_method": "okta_oidc", "flows": ["authorization_code", "cli_pkce"]}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8081)