#!/bin/bash

# SD Card Pre-provisioning Script for Fireplace Pi
# Run this on a computer with the Raspberry Pi SD card mounted
# This configures Wi-Fi and SSH before first boot

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔥 Fireplace Pi - SD Card Pre-provisioning Tool${NC}"
echo ""
echo "This tool configures a Raspberry Pi SD card for headless deployment"
echo "with pre-configured Wi-Fi networks."
echo ""

# Check if running as root (required for mount operations)
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}Note: You may need root privileges for some operations${NC}"
fi

# Function to find the boot partition
find_boot_partition() {
    echo "Looking for Raspberry Pi boot partition..."
    
    # Common mount points
    BOOT_PATHS=(
        "/media/$USER/bootfs"
        "/media/$USER/boot"
        "/media/$USER/BOOT"
        "/Volumes/boot"
        "/Volumes/bootfs"
        "/mnt/boot"
        "/mnt/bootfs"
        "$1"  # Allow user to specify path
    )
    
    for path in "${BOOT_PATHS[@]}"; do
        if [ -d "$path" ] && [ -f "$path/config.txt" -o -f "$path/cmdline.txt" ]; then
            echo -e "${GREEN}Found boot partition at: $path${NC}"
            BOOT_DIR="$path"
            return 0
        fi
    done
    
    echo -e "${RED}Could not find Raspberry Pi boot partition${NC}"
    echo "Please specify the path to the boot partition:"
    read -p "Boot partition path: " BOOT_DIR
    
    if [ ! -d "$BOOT_DIR" ]; then
        echo -e "${RED}Invalid path${NC}"
        exit 1
    fi
}

# Function to find the root partition (for NetworkManager configs)
find_root_partition() {
    echo "Looking for Raspberry Pi root partition..."
    
    # Common mount points
    ROOT_PATHS=(
        "/media/$USER/rootfs"
        "/media/$USER/root"
        "/media/$USER/writable"
        "/Volumes/rootfs"
        "/mnt/rootfs"
        "$1"  # Allow user to specify path
    )
    
    for path in "${ROOT_PATHS[@]}"; do
        if [ -d "$path/etc" ] && [ -d "$path/usr" ]; then
            echo -e "${GREEN}Found root partition at: $path${NC}"
            ROOT_DIR="$path"
            return 0
        fi
    done
    
    echo -e "${YELLOW}Could not find root partition (optional for NetworkManager)${NC}"
    ROOT_DIR=""
}

# Function to enable SSH
enable_ssh() {
    echo "Enabling SSH..."
    touch "$BOOT_DIR/ssh"
    echo -e "${GREEN}✅ SSH enabled${NC}"
}

# Function to configure Wi-Fi for first boot
configure_wifi() {
    echo ""
    echo -e "${YELLOW}Wi-Fi Configuration${NC}"
    echo "Enter your Wi-Fi network details for automatic connection on first boot."
    echo ""
    
    read -p "Wi-Fi SSID (network name): " SSID
    if [ -z "$SSID" ]; then
        echo -e "${RED}SSID cannot be empty${NC}"
        return 1
    fi
    
    read -s -p "Wi-Fi Password: " PASSWORD
    echo ""
    read -s -p "Confirm Password: " PASSWORD_CONFIRM
    echo ""
    
    if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
        echo -e "${RED}Passwords do not match${NC}"
        return 1
    fi
    
    read -p "Country Code (e.g., US, GB, DE): " COUNTRY
    COUNTRY=${COUNTRY:-US}
    
    # Determine which method to use based on Pi OS version
    if [ -d "$BOOT_DIR/firmware" ]; then
        # Newer Raspberry Pi OS (Bookworm and later)
        CONFIG_DIR="$BOOT_DIR"
    else
        # Older Raspberry Pi OS
        CONFIG_DIR="$BOOT_DIR"
    fi
    
    # Create wpa_supplicant.conf
    WPA_CONF="$CONFIG_DIR/wpa_supplicant.conf"
    
    echo "Creating Wi-Fi configuration..."
    cat > "$WPA_CONF" << EOF
country=$COUNTRY
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="$SSID"
    psk="$PASSWORD"
    key_mgmt=WPA-PSK
    priority=10
}
EOF
    
    echo -e "${GREEN}✅ Wi-Fi configuration created${NC}"
    
    # Add additional networks if desired
    while true; do
        read -p "Add another Wi-Fi network? (y/N): " add_more
        if [[ ! "$add_more" =~ ^[Yy]$ ]]; then
            break
        fi
        
        read -p "Additional SSID: " ADD_SSID
        read -s -p "Password: " ADD_PASSWORD
        echo ""
        
        cat >> "$WPA_CONF" << EOF

network={
    ssid="$ADD_SSID"
    psk="$ADD_PASSWORD"
    key_mgmt=WPA-PSK
    priority=5
}
EOF
        echo -e "${GREEN}✅ Added network '$ADD_SSID'${NC}"
    done
}

# Function to set hostname
set_hostname() {
    echo ""
    read -p "Set custom hostname (default: fireplace): " HOSTNAME
    HOSTNAME=${HOSTNAME:-fireplace}
    
    # For boot partition method (works on first boot)
    echo "$HOSTNAME" > "$BOOT_DIR/hostname"
    
    # If we have access to root partition, set it directly
    if [ ! -z "$ROOT_DIR" ] && [ -d "$ROOT_DIR/etc" ]; then
        echo "$HOSTNAME" > "$ROOT_DIR/etc/hostname"
        sed -i "s/raspberrypi/$HOSTNAME/g" "$ROOT_DIR/etc/hosts" 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✅ Hostname set to: $HOSTNAME${NC}"
}

# Function to create first-boot setup script
create_firstboot_script() {
    echo ""
    echo "Creating first-boot installation script..."
    
    FIRSTBOOT_SCRIPT="$BOOT_DIR/firstboot.sh"
    
    cat > "$FIRSTBOOT_SCRIPT" << 'EOF'
#!/bin/bash
# Fireplace Pi First Boot Setup
# This script runs once on first boot to install the fireplace software

set -e

LOG_FILE="/var/log/fireplace_firstboot.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "Starting Fireplace Pi first-boot setup..."
echo "Date: $(date)"

# Wait for network
echo "Waiting for network connection..."
for i in {1..30}; do
    if ping -c 1 8.8.8.8 &> /dev/null; then
        echo "Network connected!"
        break
    fi
    sleep 2
done

# Update system
echo "Updating system packages..."
apt update
apt upgrade -y

# Install Git
apt install -y git

# Clone the Fireplace Pi repository
echo "Cloning Fireplace Pi repository..."
cd /home/$(ls /home | head -n1)
git clone https://github.com/your-username/pi-fire.git

# Run installation
echo "Installing Fireplace Pi..."
cd pi-fire
sudo ./scripts/install.sh

# Enable services
sudo ./scripts/enable.sh

# Configure power management
sudo ./scripts/configure_power_management.sh

# Setup sudoers
sudo ./scripts/setup_sudoers.sh

# Setup scheduled shutdown
sudo ./scripts/setup_scheduled_shutdown.sh

echo "Fireplace Pi installation complete!"
echo "Access the control interface at http://$(hostname).local:8080"

# Remove this script after completion
rm /boot/firstboot.sh
rm /etc/rc.local

# Restore original rc.local if it exists
if [ -f /etc/rc.local.backup ]; then
    mv /etc/rc.local.backup /etc/rc.local
fi

# Reboot to start services
echo "Rebooting in 10 seconds..."
sleep 10
reboot
EOF
    
    chmod +x "$FIRSTBOOT_SCRIPT"
    
    # Create rc.local to run firstboot script
    if [ ! -z "$ROOT_DIR" ] && [ -d "$ROOT_DIR/etc" ]; then
        # Backup existing rc.local
        if [ -f "$ROOT_DIR/etc/rc.local" ]; then
            cp "$ROOT_DIR/etc/rc.local" "$ROOT_DIR/etc/rc.local.backup"
        fi
        
        # Create new rc.local
        cat > "$ROOT_DIR/etc/rc.local" << 'EOF'
#!/bin/bash
# Run first-boot setup if it exists
if [ -f /boot/firstboot.sh ]; then
    /boot/firstboot.sh &
fi
exit 0
EOF
        chmod +x "$ROOT_DIR/etc/rc.local"
        echo -e "${GREEN}✅ First-boot script configured${NC}"
    else
        echo -e "${YELLOW}⚠ Could not configure auto-run. Run /boot/firstboot.sh manually after boot${NC}"
    fi
}

# Function to create a summary file
create_summary() {
    SUMMARY_FILE="$BOOT_DIR/fireplace_config_summary.txt"
    
    cat > "$SUMMARY_FILE" << EOF
Fireplace Pi - Pre-provisioning Summary
========================================
Date: $(date)
Hostname: ${HOSTNAME:-fireplace}
SSH: Enabled
Wi-Fi: Configured

Networks configured:
$(grep "ssid=" "$CONFIG_DIR/wpa_supplicant.conf" 2>/dev/null | sed 's/.*ssid="\(.*\)"/  - \1/' || echo "  None")

First Boot:
- System will connect to Wi-Fi automatically
- SSH will be available
- Hostname will be: ${HOSTNAME:-fireplace}.local

To complete installation after first boot:
1. SSH into the Pi: ssh pi@${HOSTNAME:-fireplace}.local
2. Default password is 'raspberry' - change it immediately!
3. If auto-install didn't run: sudo /boot/firstboot.sh

Access the Fireplace control interface at:
http://${HOSTNAME:-fireplace}.local:8080

========================================
EOF
    
    echo ""
    echo -e "${GREEN}Configuration Summary:${NC}"
    cat "$SUMMARY_FILE"
}

# Main execution
echo "Please ensure the Raspberry Pi SD card is inserted and mounted."
echo ""

# Find partitions
find_boot_partition "$1"
find_root_partition "$2"

# Confirm we're working with the right device
echo ""
echo -e "${YELLOW}Working with:${NC}"
echo "  Boot partition: $BOOT_DIR"
[ ! -z "$ROOT_DIR" ] && echo "  Root partition: $ROOT_DIR"
echo ""
read -p "Is this correct? (y/N): " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Exiting..."
    exit 0
fi

# Perform configuration
enable_ssh
configure_wifi
set_hostname

# Optional: create first-boot script
read -p "Create automatic installation script? (y/N): " auto_install
if [[ "$auto_install" =~ ^[Yy]$ ]]; then
    create_firstboot_script
fi

# Create summary
create_summary

echo ""
echo -e "${GREEN}✅ SD card pre-provisioning complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Safely eject the SD card"
echo "2. Insert into Raspberry Pi"
echo "3. Power on the Pi"
echo "4. Wait 2-3 minutes for boot"
echo "5. SSH to: pi@${HOSTNAME:-fireplace}.local"
echo ""
echo "The configuration summary has been saved to the SD card."