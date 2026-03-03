#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/../backend-mock"

cd "$BACKEND_DIR"

# Create venv if it doesn't exist
if [ ! -d ".venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv .venv
fi

# Activate and install deps
source .venv/bin/activate
pip install -q -r requirements.txt

echo "Starting backend on http://0.0.0.0:8000 ..."
exec uvicorn main:app --host 0.0.0.0 --port 8000 --reload
