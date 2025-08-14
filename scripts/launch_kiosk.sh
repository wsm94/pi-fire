#!/bin/bash

# Fireplace Kiosk Launcher Script
# This script ensures the display environment is properly set up before launching

echo "Fireplace Kiosk Launcher starting..."

# Set display environment
export DISPLAY=:0
export XAUTHORITY=/home/pi/.Xauthority
export HOME=/home/pi

# Change to fireplace directory
cd /opt/fireplace

# Wait for X server to be available
echo "Waiting for X server..."
for i in {1..30}; do
    if xset q &>/dev/null; then
        echo "X server is ready"
        break
    fi
    echo "Waiting for X server... ($i/30)"
    sleep 2
done

# Additional delay to ensure desktop is fully loaded
echo "Waiting for desktop to stabilize..."
sleep 5

# Check if web server is running
echo "Checking web server..."
for i in {1..10}; do
    if curl -s http://localhost:8080 > /dev/null; then
        echo "Web server is ready"
        break
    fi
    echo "Waiting for web server... ($i/10)"
    sleep 2
done

# Grant display access (may be needed)
xhost +local: 2>/dev/null || true

# Start the watcher
echo "Starting Fireplace watcher..."
exec /opt/fireplace/venv/bin/python /opt/fireplace/app/watcher.py