#!/bin/bash
cd "$(dirname "$0")/../backend-mock"
source .venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
