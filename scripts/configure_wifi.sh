#!/bin/bash

# Wi-Fi Pre-provisioning Script for Fireplace Pi
# This script helps configure Wi-Fi networks before deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

echo -e "${GREEN}🔥 Fireplace Pi - Wi-Fi Configuration Tool${NC}"
echo ""

# Detect network manager
if command -v nmcli &> /dev/null; then
    NETWORK_MANAGER="NetworkManager"
elif [ -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
    NETWORK_MANAGER="wpa_supplicant"
else
    echo -e "${RED}No supported network manager found${NC}"
    exit 1
fi

echo "Detected network manager: $NETWORK_MANAGER"
echo ""

# Function to add network via NetworkManager
add_network_nm() {
    local ssid="$1"
    local password="$2"
    local priority="$3"
    
    echo "Adding network '$ssid' via NetworkManager..."
    
    if [ -z "$password" ]; then
        # Open network
        nmcli con add type wifi con-name "$ssid" ifname wlan0 ssid "$ssid"
    else
        # WPA/WPA2 network
        nmcli con add type wifi con-name "$ssid" ifname wlan0 ssid "$ssid" \
            wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$password"
    fi
    
    # Set autoconnect and priority
    nmcli con modify "$ssid" connection.autoconnect yes
    nmcli con modify "$ssid" connection.autoconnect-priority "$priority"
    
    echo -e "${GREEN}✅ Network '$ssid' added successfully${NC}"
}

# Function to add network via wpa_supplicant
add_network_wpa() {
    local ssid="$1"
    local password="$2"
    local priority="$3"
    
    echo "Adding network '$ssid' to wpa_supplicant..."
    
    # Backup existing configuration
    if [ ! -f /etc/wpa_supplicant/wpa_supplicant.conf.backup ]; then
        cp /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf.backup
        echo "Created backup at /etc/wpa_supplicant/wpa_supplicant.conf.backup"
    fi
    
    # Generate network block
    if [ -z "$password" ]; then
        # Open network
        cat >> /etc/wpa_supplicant/wpa_supplicant.conf << EOF

network={
    ssid="$ssid"
    key_mgmt=NONE
    priority=$priority
}
EOF
    else
        # WPA/WPA2 network - use wpa_passphrase to generate secure config
        wpa_passphrase "$ssid" "$password" | sed "s/^}/\tpriority=$priority\n}/" >> /etc/wpa_supplicant/wpa_supplicant.conf
    fi
    
    echo -e "${GREEN}✅ Network '$ssid' added to wpa_supplicant${NC}"
}

# Function to configure a single network
configure_network() {
    local network_num="$1"
    
    echo -e "${YELLOW}Network #$network_num Configuration${NC}"
    echo "--------------------------------"
    
    read -p "SSID (network name): " ssid
    if [ -z "$ssid" ]; then
        echo -e "${RED}SSID cannot be empty${NC}"
        return 1
    fi
    
    read -s -p "Password (press Enter for open network): " password
    echo ""
    
    if [ ! -z "$password" ]; then
        read -s -p "Confirm password: " password_confirm
        echo ""
        
        if [ "$password" != "$password_confirm" ]; then
            echo -e "${RED}Passwords do not match${NC}"
            return 1
        fi
    fi
    
    read -p "Priority (higher = preferred, default 10): " priority
    priority=${priority:-10}
    
    # Add network based on manager
    if [ "$NETWORK_MANAGER" = "NetworkManager" ]; then
        add_network_nm "$ssid" "$password" "$priority"
    else
        add_network_wpa "$ssid" "$password" "$priority"
    fi
    
    echo ""
    return 0
}

# Function to create a Wi-Fi configuration file for deployment
create_deployment_config() {
    local config_file="/boot/firmware/wifi-config.txt"
    
    echo -e "${YELLOW}Creating deployment configuration...${NC}"
    
    cat > "$config_file" << 'EOF'
# Fireplace Pi Wi-Fi Configuration
# This file contains the Wi-Fi networks configured for this device
# Generated on: 
EOF
    echo "# $(date)" >> "$config_file"
    echo "" >> "$config_file"
    
    if [ "$NETWORK_MANAGER" = "NetworkManager" ]; then
        echo "# NetworkManager Configuration:" >> "$config_file"
        nmcli -t -f NAME,UUID con show | grep -v "^lo:" >> "$config_file"
    else
        echo "# wpa_supplicant Configuration:" >> "$config_file"
        grep -A 4 "network={" /etc/wpa_supplicant/wpa_supplicant.conf | grep "ssid=" >> "$config_file"
    fi
    
    echo -e "${GREEN}Configuration saved to $config_file${NC}"
}

# Main menu
main_menu() {
    while true; do
        echo -e "${YELLOW}Wi-Fi Configuration Menu${NC}"
        echo "1) Add new Wi-Fi network"
        echo "2) List configured networks"
        echo "3) Remove a network"
        echo "4) Test connectivity"
        echo "5) Create deployment config"
        echo "6) Exit"
        echo ""
        read -p "Select option (1-6): " choice
        
        case $choice in
            1)
                network_count=1
                while true; do
                    configure_network $network_count
                    network_count=$((network_count + 1))
                    
                    read -p "Add another network? (y/N): " add_more
                    if [[ ! "$add_more" =~ ^[Yy]$ ]]; then
                        break
                    fi
                done
                ;;
            2)
                echo -e "${YELLOW}Configured Networks:${NC}"
                if [ "$NETWORK_MANAGER" = "NetworkManager" ]; then
                    nmcli con show | grep wifi
                else
                    grep "ssid=" /etc/wpa_supplicant/wpa_supplicant.conf | sed 's/.*ssid="\(.*\)"/  - \1/'
                fi
                echo ""
                ;;
            3)
                echo -e "${YELLOW}Remove Network${NC}"
                if [ "$NETWORK_MANAGER" = "NetworkManager" ]; then
                    nmcli con show | grep wifi
                    read -p "Enter network name to remove: " network_name
                    nmcli con delete "$network_name"
                else
                    echo -e "${RED}Manual editing required for wpa_supplicant${NC}"
                    echo "Edit /etc/wpa_supplicant/wpa_supplicant.conf to remove networks"
                fi
                echo ""
                ;;
            4)
                echo -e "${YELLOW}Testing connectivity...${NC}"
                if ping -c 3 8.8.8.8 &> /dev/null; then
                    echo -e "${GREEN}✅ Internet connection is working${NC}"
                    ip_addr=$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
                    echo "Wi-Fi IP address: $ip_addr"
                else
                    echo -e "${RED}❌ No internet connection${NC}"
                    echo "Current Wi-Fi status:"
                    ip link show wlan0
                fi
                echo ""
                ;;
            5)
                create_deployment_config
                echo ""
                ;;
            6)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                echo ""
                ;;
        esac
    done
}

# Check for command line mode
if [ "$1" = "--quick" ]; then
    # Quick mode for single network
    echo "Quick Wi-Fi Setup Mode"
    echo ""
    configure_network 1
    
    echo ""
    echo "Restarting network services..."
    if [ "$NETWORK_MANAGER" = "NetworkManager" ]; then
        systemctl restart NetworkManager
    else
        wpa_cli -i wlan0 reconfigure
    fi
    
    echo -e "${GREEN}Wi-Fi configuration complete!${NC}"
else
    # Interactive menu mode
    main_menu
fi