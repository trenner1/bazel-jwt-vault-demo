#!/usr/bin/env python3
"""
Simple startup script for the broker application.
"""
import uvicorn
import os

if __name__ == "__main__":
    # Ensure we're in the broker directory where the keys are located
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    
    # Start the uvicorn server
    uvicorn.run("app:app", host="0.0.0.0", port=8081, reload=True)