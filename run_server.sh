#!/bin/bash

# Run the Flask server with proper Python path
# This script ensures the app can find all its modules

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Add the current directory to Python path so imports work
export PYTHONPATH="${SCRIPT_DIR}:${SCRIPT_DIR}/app:${PYTHONPATH}"

# Check if running in venv or system
if [ -d "venv" ]; then
    echo "Using virtual environment..."
    source venv/bin/activate
    python app/server.py
elif [ -d "/opt/fireplace/venv" ]; then
    echo "Using /opt/fireplace virtual environment..."
    /opt/fireplace/venv/bin/python app/server.py
else
    echo "Using system Python..."
    python3 app/server.py
fi