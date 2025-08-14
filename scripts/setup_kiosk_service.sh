#!/bin/bash

# Setup script that configures the kiosk service for the current user

# Get the current user (or use first argument)
CURRENT_USER=${1:-$USER}

if [ -z "$CURRENT_USER" ]; then
    echo "Error: Could not determine username"
    echo "Usage: $0 [username]"
    exit 1
fi

echo "Setting up kiosk service for user: $CURRENT_USER"

# Create the service file with the correct username
sed "s/USER_PLACEHOLDER/$CURRENT_USER/g" systemd/fire-kiosk.service.template > /tmp/fire-kiosk.service

# Copy to systemd
sudo cp /tmp/fire-kiosk.service /etc/systemd/system/

# Update the launch script with correct username
sudo cat > /opt/fireplace/scripts/launch_kiosk.sh << EOF
#!/bin/bash

# Fireplace Kiosk Launcher Script
echo "Fireplace Kiosk Launcher starting for user: $CURRENT_USER"

# Set display environment
export DISPLAY=:0
export XAUTHORITY=/home/$CURRENT_USER/.Xauthority
export HOME=/home/$CURRENT_USER

# Change to fireplace directory
cd /opt/fireplace

# Wait for X server to be available
echo "Waiting for X server..."
for i in {1..30}; do
    if xset q &>/dev/null; then
        echo "X server is ready"
        break
    fi
    echo "Waiting for X server... (\$i/30)"
    sleep 2
done

# Additional delay
sleep 5

# Check if web server is running
echo "Checking web server..."
if curl -s http://localhost:8080 > /dev/null; then
    echo "Web server is ready"
else
    echo "Warning: Web server may not be ready, continuing anyway..."
fi

# Grant display access
xhost +local: 2>/dev/null || true

# Start the watcher
echo "Starting Fireplace watcher..."
exec /opt/fireplace/venv/bin/python /opt/fireplace/app/watcher.py
EOF

# Set permissions
sudo chmod +x /opt/fireplace/scripts/launch_kiosk.sh
sudo chown $CURRENT_USER:$CURRENT_USER /opt/fireplace/scripts/launch_kiosk.sh

# Add user to fireplace group
sudo usermod -a -G fireplace $CURRENT_USER

# Reload systemd
sudo systemctl daemon-reload

echo "Setup complete for user: $CURRENT_USER"
echo "You can now start the service with:"
echo "  sudo systemctl start fire-kiosk.service"