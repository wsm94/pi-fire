#!/bin/bash

# Setup sudoers to allow fireplace user to control the kiosk service
# This script must be run as root

if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

echo "Setting up sudoers for fireplace service control..."

# Create sudoers file for fireplace user
cat > /etc/sudoers.d/fireplace-kiosk << 'EOF'
# Allow fireplace user to control fire-kiosk service without password
fireplace ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop fire-kiosk.service
fireplace ALL=(ALL) NOPASSWD: /usr/bin/systemctl start fire-kiosk.service
fireplace ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart fire-kiosk.service
fireplace ALL=(ALL) NOPASSWD: /usr/bin/systemctl status fire-kiosk.service

# Allow fireplace user to control system power without password
fireplace ALL=(ALL) NOPASSWD: /usr/sbin/shutdown -h *
fireplace ALL=(ALL) NOPASSWD: /usr/sbin/shutdown -r *

# Also allow the main user (will) to control services and power
will ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop fire-kiosk.service
will ALL=(ALL) NOPASSWD: /usr/bin/systemctl start fire-kiosk.service
will ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart fire-kiosk.service
will ALL=(ALL) NOPASSWD: /usr/bin/systemctl status fire-kiosk.service
will ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop fire-web.service
will ALL=(ALL) NOPASSWD: /usr/bin/systemctl start fire-web.service
will ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart fire-web.service
will ALL=(ALL) NOPASSWD: /usr/bin/systemctl status fire-web.service
will ALL=(ALL) NOPASSWD: /usr/sbin/shutdown -h *
will ALL=(ALL) NOPASSWD: /usr/sbin/shutdown -r *
EOF

# Set correct permissions
chmod 440 /etc/sudoers.d/fireplace-kiosk

echo "Sudoers configuration complete!"
echo "The fireplace user can now control the kiosk service without a password."