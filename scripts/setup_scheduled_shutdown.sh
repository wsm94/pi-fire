#!/bin/bash

# Setup scheduled shutdown systemd services
# This script installs and configures the scheduled shutdown timer

if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

echo "Setting up scheduled shutdown services..."

# Copy service files to systemd directory
echo "Installing service files..."
cp systemd/fireplace-scheduled-shutdown.service /etc/systemd/system/
cp systemd/fireplace-scheduled-shutdown.timer /etc/systemd/system/

# Make the scheduled shutdown script executable
chmod +x /opt/fireplace/app/scheduled_shutdown.py

# Create log directory if it doesn't exist
mkdir -p /var/log/fireplace
chown fireplace:fireplace /var/log/fireplace

# Reload systemd to recognize new services
echo "Reloading systemd..."
systemctl daemon-reload

# Enable but don't start the timer (it will be managed by the web interface)
echo "Enabling scheduled shutdown timer..."
systemctl enable fireplace-scheduled-shutdown.timer

echo "✅ Scheduled shutdown services installed!"
echo ""
echo "The scheduled shutdown timer is now available but disabled by default."
echo "Use the web interface (hamburger menu → Scheduled Shutdown) to configure and enable it."
echo ""
echo "To manually check the timer status:"
echo "  sudo systemctl status fireplace-scheduled-shutdown.timer"
echo ""
echo "To view scheduled shutdown logs:"
echo "  sudo journalctl -u fireplace-scheduled-shutdown.service"
echo "  tail -f /var/log/fireplace/scheduled_shutdown.log"