#!/bin/bash

set -e

echo "🔥 Enabling Fireplace Pi services..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Copy service files
echo "Installing systemd services..."
cp systemd/fire-web.service /etc/systemd/system/
cp systemd/fire-kiosk.service /etc/systemd/system/

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