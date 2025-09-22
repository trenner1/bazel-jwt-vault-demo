#!/usr/bin/env python3
"""
Example: Bazel Build Authentication using Authorization Code Flow with PKCE

This demonstrates how a Bazel rule or toolchain would authenticate 
users during build time using Okta Authorization Code Flow with PKCE.
This approach works with existing Okta Web Applications.

Usage:
    python bazel_auth_example.py
"""

import asyncio
import httpx
import time
import json
import sys
import webbrowser
from urllib.parse import urlparse, parse_qs

BROKER_URL = "http://localhost:8081"

async def authenticate_for_bazel_build(pipeline="bazel-build", repo="example-repo", target="//my:target"):
    """
    Complete authentication flow for Bazel build using PKCE
    
    This would typically be called from:
    - Bazel custom rule implementation
    - Bazel toolchain setup
    - Build script before accessing secrets
    """
    
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            # Step 1: Start CLI authentication flow
            print("🔄 Starting authentication for Bazel build...")
            start_response = await client.post(f"{BROKER_URL}/cli/start")
            
            if start_response.status_code != 200:
                print(f"❌ Failed to start authentication: {start_response.text}")
                return None
                
            auth_data = start_response.json()
            auth_url = auth_data["auth_url"]
            state = auth_data["state"]
            
            # Step 2: Open browser for user authentication
            print("\n" + "="*60)
            print("🔐 AUTHENTICATION REQUIRED FOR BAZEL BUILD")
            print("="*60)
            print("🌐 Opening browser for Okta authentication...")
            print(f"🔗 URL: {auth_url}")
            print("="*60)
            
            # Open browser automatically
            webbrowser.open(auth_url)
            
            # Step 3: Wait for user to complete authentication
            print("\n⏳ Please complete authentication in your browser...")
            print("📋 After authentication, you'll be redirected to a callback page.")
            print("� The page will show a JSON response with authentication details.")
            print("📝 Copy the 'session_id' value from that JSON response:")
            
            session_id = input("\n� Paste session_id: ").strip().strip('"')
            
            if not session_id:
                print("❌ No session_id provided")
                return None
            
            print(f"✅ Using session: {session_id}")
            
            # Step 4: Exchange session for constrained Vault token
            print(f"🎫 Getting Vault token for build context...")
            vault_response = await client.post(
                f"{BROKER_URL}/exchange",
                json={
                    "session_id": session_id,
                    "pipeline": pipeline,
                    "repo": repo,
                    "target": target
                }
            )
            
            if vault_response.status_code == 200:
                token_data = vault_response.json()
                user_email = token_data['metadata']['user']
                print(f"🏗️ Build token created:")
                print(f"   - Team: {token_data['metadata']['team']}")
                print(f"   - Policies: {', '.join(token_data['policies'])}")
                print(f"   - TTL: {token_data['ttl']}s")
                print(f"   - Uses: {token_data['uses_remaining']}")
                
                # Return token for Bazel to use
                return {
                    "vault_token": token_data["token"],
                    "team": token_data["metadata"]["team"],
                    "user": user_email,
                    "policies": token_data["policies"]
                }
            else:
                print(f"❌ Failed to get Vault token: {vault_response.text}")
                return None
            
        except Exception as e:
            print(f"💥 Authentication failed: {e}")
            return None

async def main():
    """Example usage"""
    print("🏗️ Bazel Build Authentication Example")
    print("=====================================")
    
    # Simulate Bazel build context
    build_context = {
        "pipeline": "ci-build-123",
        "repo": "my-awesome-project", 
        "target": "//apps/mobile:release"
    }
    
    # Authenticate for build
    auth_result = await authenticate_for_bazel_build(**build_context)
    
    if auth_result:
        print("\n✅ Authentication successful!")
        print(f"🔐 Vault token available for team: {auth_result['team']}")
        print(f"👤 Authenticated as: {auth_result['user']}")
        print("\n🏗️ Bazel build can now proceed with team-scoped access to:")
        
        for policy in auth_result['policies']:
            if 'mobile' in policy:
                print("   📱 Mobile secrets and certificates")
            elif 'backend' in policy:
                print("   ⚙️ Backend API keys and database credentials")
            elif 'frontend' in policy:
                print("   🌐 Frontend build tokens and CDN keys")
            elif 'base' in policy:
                print("   🔧 Base build tools and common secrets")
                
        print(f"\n💡 Token expires in {auth_result.get('ttl', 'unknown')} seconds")
        
        # In real Bazel usage, you'd now:
        # 1. Set VAULT_TOKEN environment variable
        # 2. Use vault CLI or API to fetch specific secrets
        # 3. Continue with build process
        
    else:
        print("\n❌ Authentication failed!")
        print("🏗️ Bazel build cannot proceed without authentication")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())