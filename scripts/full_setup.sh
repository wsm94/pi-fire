#!/bin/bash

# Full Fireplace Pi Setup Script
# This script performs a complete installation and configuration
# Run this on a fresh Raspberry Pi to get everything working

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}"
echo "🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥"
echo "🔥                                                                🔥"
echo "🔥                    Fireplace Pi Setup                         🔥"
echo "🔥                  Complete Installation                        🔥"
echo "🔥                                                                🔥"
echo "🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥"
echo -e "${NC}"
echo ""
echo "This script will install and configure the complete Fireplace Pi system"
echo "including ad blocking, power management, and remote control features."
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Get the actual user (not root)
ACTUAL_USER="${SUDO_USER:-$USER}"
if [ "$ACTUAL_USER" = "root" ]; then
    echo -e "${YELLOW}Warning: Running as root user. Some features may not work as expected.${NC}"
    ACTUAL_USER="pi"  # Default fallback
fi

echo -e "${BLUE}Setting up for user: $ACTUAL_USER${NC}"
echo ""

# Function to show progress
show_progress() {
    local step="$1"
    local total="$2" 
    local message="$3"
    local percent=$((step * 100 / total))
    local filled=$((percent / 5))
    local empty=$((20 - filled))
    
    printf "\r${BLUE}[%s%s] %d%% - %s${NC}" \
        "$(printf "%*s" $filled | tr ' ' '█')" \
        "$(printf "%*s" $empty | tr ' ' '░')" \
        "$percent" "$message"
    
    if [ "$step" -eq "$total" ]; then
        echo ""
    fi
}

# Function to run with progress
run_step() {
    local step="$1"
    local total="$2"
    local message="$3"
    local command="$4"
    
    show_progress "$step" "$total" "$message"
    
    if ! eval "$command" >> /tmp/fireplace_install.log 2>&1; then
        echo ""
        echo -e "${RED}❌ Failed: $message${NC}"
        echo "Check /tmp/fireplace_install.log for details"
        exit 1
    fi
    
    sleep 1  # Brief pause to show progress
}

# Create log file
echo "Fireplace Pi Installation Log - $(date)" > /tmp/fireplace_install.log

TOTAL_STEPS=11
CURRENT_STEP=0

# Step 1: Update system
CURRENT_STEP=$((CURRENT_STEP + 1))
run_step $CURRENT_STEP $TOTAL_STEPS "Updating system packages" "apt update && apt upgrade -y"

# Step 2: Install dependencies
CURRENT_STEP=$((CURRENT_STEP + 1))
run_step $CURRENT_STEP $TOTAL_STEPS "Installing system dependencies" "./scripts/install.sh"

# Step 3: Enable services
CURRENT_STEP=$((CURRENT_STEP + 1))
run_step $CURRENT_STEP $TOTAL_STEPS "Enabling systemd services" "./scripts/enable.sh"

# Step 4: Configure sudo permissions
CURRENT_STEP=$((CURRENT_STEP + 1))
run_step $CURRENT_STEP $TOTAL_STEPS "Setting up sudo permissions" "./scripts/setup_sudoers.sh"

# Step 5: Setup scheduled shutdown
CURRENT_STEP=$((CURRENT_STEP + 1))
run_step $CURRENT_STEP $TOTAL_STEPS "Configuring scheduled shutdown" "./scripts/setup_scheduled_shutdown.sh"

# Step 6: Configure power management
CURRENT_STEP=$((CURRENT_STEP + 1))
run_step $CURRENT_STEP $TOTAL_STEPS "Optimizing power management" "./scripts/configure_power_management.sh"

# Step 7: Configure Wi-Fi (interactive)
CURRENT_STEP=$((CURRENT_STEP + 1))
show_progress $CURRENT_STEP $TOTAL_STEPS "Configuring Wi-Fi networks"
echo ""
echo ""
echo -e "${YELLOW}Wi-Fi Configuration${NC}"
echo "Configure Wi-Fi networks for deployment (optional but recommended)"
echo ""
read -p "Configure Wi-Fi networks now? (y/N): " configure_wifi

if [[ "$configure_wifi" =~ ^[Yy]$ ]]; then
    ./scripts/configure_wifi.sh
else
    echo "Skipping Wi-Fi configuration (can be done later)"
fi

# Step 8: Start services
CURRENT_STEP=$((CURRENT_STEP + 1))
run_step $CURRENT_STEP $TOTAL_STEPS "Starting web service" "systemctl start fire-web.service"

# Step 9: Check service status
CURRENT_STEP=$((CURRENT_STEP + 1))
run_step $CURRENT_STEP $TOTAL_STEPS "Verifying web service" "systemctl is-active fire-web.service"

# Step 10: Add sample content
CURRENT_STEP=$((CURRENT_STEP + 1))
show_progress $CURRENT_STEP $TOTAL_STEPS "Setting up sample content"
echo ""

# Create a sample video if none exist
if [ ! "$(ls -A /opt/fireplace/videos/*.mp4 2>/dev/null)" ]; then
    echo ""
    echo -e "${YELLOW}No video files found. Adding sample content...${NC}"
    
    # Create a simple test pattern video using ffmpeg if available
    if command -v ffmpeg &> /dev/null; then
        echo "Creating test pattern video..."
        ffmpeg -f lavfi -i testsrc2=duration=10:size=1920x1080:rate=30 \
               -f lavfi -i sine=frequency=1000:duration=10 \
               -c:v libx264 -preset fast -crf 23 \
               -c:a aac -shortest \
               /opt/fireplace/videos/test-pattern.mp4 >> /tmp/fireplace_install.log 2>&1 || true
        
        chown fireplace:fireplace /opt/fireplace/videos/test-pattern.mp4 2>/dev/null || true
    fi
    
    # Update the README with download suggestions
    cat >> /opt/fireplace/videos/README.md << 'EOF'

## Getting Started

To add fireplace videos:

1. Download MP4 videos from:
   - Archive.org (search "fireplace" or "fire")
   - YouTube (use youtube-dl or yt-dlp)
   - Your own recordings

2. Copy them to this directory:
   sudo cp your-video.mp4 /opt/fireplace/videos/
   sudo chown fireplace:fireplace /opt/fireplace/videos/*.mp4

3. Refresh the web interface to see new videos

## Recommended Video Specs
- Format: MP4 (H.264)
- Resolution: 1920x1080 or higher
- Duration: 1+ hours for best looping experience
- Bitrate: 2-8 Mbps
EOF
fi

# Step 11: Final verification
CURRENT_STEP=$((CURRENT_STEP + 1))
run_step $CURRENT_STEP $TOTAL_STEPS "Final system verification" "curl -s http://localhost:8080 > /dev/null"

echo ""
echo -e "${GREEN}✅ Fireplace Pi installation completed successfully!${NC}"
echo ""

# Get system information
HOSTNAME=$(hostname)
IP_ADDRESS=$(ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
if [ -z "$IP_ADDRESS" ]; then
    IP_ADDRESS=$(ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
fi

echo -e "${BLUE}🎉 Installation Summary${NC}"
echo "=================================="
echo "Hostname: $HOSTNAME"
echo "IP Address: ${IP_ADDRESS:-Not available}"
echo "Web Interface: http://$HOSTNAME.local:8080"
if [ ! -z "$IP_ADDRESS" ]; then
    echo "              http://$IP_ADDRESS:8080"
fi
echo ""
echo -e "${GREEN}Services Status:${NC}"
systemctl is-active fire-web.service && echo "  ✅ Web Control: Running" || echo "  ❌ Web Control: Not running"
systemctl is-enabled fire-web.service && echo "  ✅ Auto-start: Enabled" || echo "  ❌ Auto-start: Disabled"
echo ""

echo -e "${YELLOW}Features Configured:${NC}"
echo "  ✅ YouTube & offline video playback"
echo "  ✅ Mobile/laptop remote control"
echo "  ✅ Favorites management"
echo "  ✅ Power controls (shutdown/reboot)"
echo "  ✅ Scheduled shutdown (configurable)"
echo "  ✅ Power management optimization"
echo "  ✅ Auto-start on boot"
echo ""

echo -e "${YELLOW}Quick Start:${NC}"
echo "1. Add fireplace videos to /opt/fireplace/videos/"
echo "2. Access web control: http://$HOSTNAME.local:8080"
echo "3. Test kiosk mode: sudo systemctl start fire-kiosk.service"
echo "4. Configure favorites and scheduled shutdown"
echo ""

echo -e "${BLUE}Troubleshooting:${NC}"
echo "  View logs: sudo journalctl -u fire-web.service -f"
echo "  Wi-Fi setup: sudo ./scripts/configure_wifi.sh"
echo ""

# Ask about kiosk mode
echo -e "${YELLOW}Optional: Start Kiosk Mode${NC}"
echo "The kiosk mode displays the fireplace in fullscreen on the connected display."
echo ""
read -p "Start kiosk mode now? (y/N): " start_kiosk

if [[ "$start_kiosk" =~ ^[Yy]$ ]]; then
    echo "Starting kiosk mode..."
    systemctl start fire-kiosk.service
    echo -e "${GREEN}✅ Kiosk mode started!${NC}"
    echo "The fireplace should now be displayed in fullscreen."
    echo "Use the web interface to control it remotely."
else
    echo "Kiosk mode can be started later with:"
    echo "  sudo systemctl start fire-kiosk.service"
fi

echo ""
echo -e "${GREEN}🔥 Fireplace Pi is ready! Enjoy your cozy fireplace! 🔥${NC}"
echo ""

# Cleanup
rm -f /tmp/fireplace_install.log