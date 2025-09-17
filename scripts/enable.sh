#!/bin/bash

set -e

echo "🔥 Enabling Fireplace Pi services..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Determine the actual user (not root)
ACTUAL_USER="${SUDO_USER:-$USER}"
if [ "$ACTUAL_USER" = "root" ]; then
    echo "Warning: Cannot determine actual user. Defaulting to 'fireplace'"
    ACTUAL_USER="fireplace"
fi

echo "Configuring services for user: $ACTUAL_USER"

# Copy and configure service files
echo "Installing systemd services..."
cp systemd/fire-web.service /etc/systemd/system/
cp systemd/fire-kiosk.service /etc/systemd/system/

# Update the user in service files
sed -i "s/User=fireplace/User=$ACTUAL_USER/g" /etc/systemd/system/fire-web.service
sed -i "s/Group=fireplace/Group=$ACTUAL_USER/g" /etc/systemd/system/fire-web.service
sed -i "s/User=fireplace/User=$ACTUAL_USER/g" /etc/systemd/system/fire-kiosk.service
sed -i "s/Group=fireplace/Group=$ACTUAL_USER/g" /etc/systemd/system/fire-kiosk.service

# Set the correct home directory paths for kiosk service
USER_HOME=$(eval echo "~$ACTUAL_USER")
sed -i "s|# Environment=\"XAUTHORITY=/home/\[USER\]/\.Xauthority\"|Environment=\"XAUTHORITY=$USER_HOME/.Xauthority\"|g" /etc/systemd/system/fire-kiosk.service
sed -i "s|# Environment=\"HOME=/home/\[USER\]\"|Environment=\"HOME=$USER_HOME\"|g" /etc/systemd/system/fire-kiosk.service

# Reload systemd
systemctl daemon-reload

# Enable services
echo "Enabling services..."
systemctl enable fire-web.service
systemctl enable fire-kiosk.service

# Start web service immediately
echo "Starting web service..."
systemctl start fire-web.service

echo "✅ Services enabled!"
echo ""
echo "Service status:"
systemctl status fire-web.service --no-pager -l
echo ""
echo "Commands:"
echo "  Start kiosk: sudo systemctl start fire-kiosk.service"
echo "  Stop all:    sudo systemctl stop fire-web.service fire-kiosk.service"
echo "  View logs:   sudo journalctl -u fire-web.service -f"
echo "              sudo journalctl -u fire-kiosk.service -f"
echo ""
echo "Access control at: http://$(hostname).local:8080"