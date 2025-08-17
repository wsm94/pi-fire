#!/bin/bash

# Configure Raspberry Pi 5 power management settings
# This script configures POWER_OFF_ON_HALT=1 for minimal standby power consumption

if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

echo "Configuring Raspberry Pi 5 power management..."

# Check if this is a Raspberry Pi 5
PI_MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
if [[ ! "$PI_MODEL" =~ "Raspberry Pi 5" ]]; then
    echo "Warning: This script is designed for Raspberry Pi 5. Current model: $PI_MODEL"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Configure POWER_OFF_ON_HALT=1 for minimal standby power
echo "Setting POWER_OFF_ON_HALT=1 for minimal standby power consumption..."

# Check if the setting already exists in config.txt
if grep -q "^POWER_OFF_ON_HALT=" /boot/firmware/config.txt; then
    # Update existing setting
    sed -i 's/^POWER_OFF_ON_HALT=.*/POWER_OFF_ON_HALT=1/' /boot/firmware/config.txt
    echo "Updated existing POWER_OFF_ON_HALT setting to 1"
else
    # Add new setting
    echo "" >> /boot/firmware/config.txt
    echo "# Power management - minimal standby power consumption" >> /boot/firmware/config.txt
    echo "POWER_OFF_ON_HALT=1" >> /boot/firmware/config.txt
    echo "Added POWER_OFF_ON_HALT=1 to config.txt"
fi

# Also check for older Pi models that might use /boot/config.txt
if [ -f /boot/config.txt ] && [ ! -L /boot/config.txt ]; then
    if grep -q "^POWER_OFF_ON_HALT=" /boot/config.txt; then
        sed -i 's/^POWER_OFF_ON_HALT=.*/POWER_OFF_ON_HALT=1/' /boot/config.txt
        echo "Updated POWER_OFF_ON_HALT in /boot/config.txt as well"
    else
        echo "" >> /boot/config.txt
        echo "# Power management - minimal standby power consumption" >> /boot/config.txt
        echo "POWER_OFF_ON_HALT=1" >> /boot/config.txt
        echo "Added POWER_OFF_ON_HALT=1 to /boot/config.txt as well"
    fi
fi

# Configure other power-related settings for kiosk use
echo "Configuring additional power management settings..."

# Disable WiFi power saving (can cause connection drops in kiosk mode)
if ! grep -q "iwconfig wlan0 power off" /etc/rc.local; then
    sed -i '/^exit 0/i # Disable WiFi power saving for kiosk stability\niwconfig wlan0 power off 2>/dev/null || true\n' /etc/rc.local
    echo "Disabled WiFi power saving for better kiosk stability"
fi

# Disable unnecessary services to reduce power consumption
SERVICES_TO_DISABLE=(
    "bluetooth"
    "hciuart" 
    "triggerhappy"
    "dphys-swapfile"
)

for service in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl is-enabled "$service" >/dev/null 2>&1; then
        systemctl disable "$service"
        echo "Disabled $service to reduce power consumption"
    fi
done

echo ""
echo "Power management configuration complete!"
echo ""
echo "Changes made:"
echo "  ✓ POWER_OFF_ON_HALT=1 (minimal standby power: 3-4mA instead of ~100mA)"
echo "  ✓ Disabled WiFi power saving (prevents connection drops)"
echo "  ✓ Disabled unnecessary services for lower power consumption"
echo ""
echo "NOTE: A reboot is required for these changes to take effect."
echo ""
read -p "Reboot now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Rebooting in 5 seconds..."
    sleep 5
    reboot
else
    echo "Remember to reboot to apply power management settings."
fi