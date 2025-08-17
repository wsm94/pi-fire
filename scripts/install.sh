#!/bin/bash

set -e

FIREPLACE_DIR="/opt/fireplace"
SERVICE_USER="fireplace"
LOG_DIR="/var/log/fireplace"

echo "🔥 Installing Fireplace Pi..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Create fireplace user if it doesn't exist
if ! id "$SERVICE_USER" &>/dev/null; then
    echo "Creating fireplace user..."
    useradd -r -s /bin/false -d "$FIREPLACE_DIR" "$SERVICE_USER"
fi

# Install system dependencies
echo "Installing system dependencies..."
apt update
apt install -y python3 python3-pip python3-venv chromium-browser avahi-daemon

# Create directories
echo "Creating directories..."
mkdir -p "$FIREPLACE_DIR"/{config,videos,logs,chromium-profile}
mkdir -p "$LOG_DIR"

# Copy application files
echo "Copying application files..."
cp -r app "$FIREPLACE_DIR/"
cp -r config "$FIREPLACE_DIR/"
cp requirements.txt "$FIREPLACE_DIR/"

# Set up Python virtual environment
echo "Setting up Python environment..."
cd "$FIREPLACE_DIR"
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Set permissions
echo "Setting permissions..."
chown -R "$SERVICE_USER:$SERVICE_USER" "$FIREPLACE_DIR"
chown -R "$SERVICE_USER:$SERVICE_USER" "$LOG_DIR"
chmod +x "$FIREPLACE_DIR/app/server.py"
chmod +x "$FIREPLACE_DIR/app/watcher.py"

# Enable avahi-daemon for mDNS
systemctl enable avahi-daemon
systemctl start avahi-daemon

# Create sample videos directory with README
cat > "$FIREPLACE_DIR/videos/README.md" << EOF
# Fireplace Videos

Place your fireplace video files in this directory.

Supported formats:
- .mp4
- .webm  
- .mkv
- .avi
- .mov

Videos will be automatically detected and available in the offline player.

## Sample Videos

You can download free fireplace videos from:
- https://archive.org (search for "fireplace" or "fire")  
- Creative Commons licensed videos
- Your own recorded content

Make sure you have the rights to use any videos you place here.
EOF

# Create initial state file if it doesn't exist
if [ ! -f "$FIREPLACE_DIR/state.json" ]; then
    echo "Creating initial state file..."
    cp "$FIREPLACE_DIR/config/state_default.json" "$FIREPLACE_DIR/state.json"
fi

chown "$SERVICE_USER:$SERVICE_USER" "$FIREPLACE_DIR/state.json"
chown "$SERVICE_USER:$SERVICE_USER" "$FIREPLACE_DIR/videos/README.md"

# Configure power management for Pi 5
echo "Configuring power management..."
if [ -f "scripts/configure_power_management.sh" ]; then
    bash scripts/configure_power_management.sh
else
    echo "Power management script not found, skipping..."
fi

# Setup uBlock Origin for ad blocking
echo "Setting up uBlock Origin..."
if [ -f "scripts/setup_ublock_origin.sh" ]; then
    bash scripts/setup_ublock_origin.sh
else
    echo "uBlock Origin setup script not found, skipping..."
fi

echo "✅ Fireplace Pi installation completed!"
echo ""
echo "Next steps:"
echo "1. Add some video files to $FIREPLACE_DIR/videos/"
echo "2. Install systemd services: sudo ./scripts/enable.sh"
echo "3. Configure sudo permissions: sudo ./scripts/setup_sudoers.sh"
echo "4. Setup scheduled shutdown: sudo ./scripts/setup_scheduled_shutdown.sh"
echo "5. Access the control interface at http://$(hostname).local:8080"
echo ""
echo "For development/testing:"
echo "cd $FIREPLACE_DIR && source venv/bin/activate && python app/server.py"