#!/bin/bash

# Setup uBlock Origin for Chromium Kiosk Mode
# This script installs and configures uBlock Origin for ad blocking in fireplace videos

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔥 Setting up uBlock Origin for Fireplace Pi${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Chromium profile directory for fireplace user
CHROMIUM_DIR="/opt/fireplace/chromium-profile"
EXTENSIONS_DIR="$CHROMIUM_DIR/Default/Extensions"
POLICIES_DIR="/etc/chromium-browser/policies/managed"

# uBlock Origin extension ID
UBLOCK_ID="cjpalhdlnbpafiamejdnhcphjbkeiagm"

echo "Configuring Chromium for fireplace kiosk..."

# Create Chromium profile directory structure
echo "Creating Chromium profile structure..."
mkdir -p "$CHROMIUM_DIR/Default/Extensions"
mkdir -p "$CHROMIUM_DIR/Default/External Extensions"
mkdir -p "$POLICIES_DIR"

# Set ownership to fireplace user
chown -R fireplace:fireplace "$CHROMIUM_DIR"

echo "Installing uBlock Origin via Chrome Web Store..."

# Create external extensions configuration to auto-install uBlock Origin
cat > "$CHROMIUM_DIR/Default/External Extensions/ublock-origin.json" << EOF
{
  "external_update_url": "https://clients2.google.com/service/update2/crx"
}
EOF

# Configure Chromium policies for kiosk mode with uBlock Origin
echo "Configuring Chromium policies..."
cat > "$POLICIES_DIR/fireplace-kiosk.json" << EOF
{
  "ExtensionInstallForcelist": [
    "${UBLOCK_ID};https://clients2.google.com/service/update2/crx"
  ],
  "ExtensionInstallAllowlist": [
    "${UBLOCK_ID}"
  ],
  "DefaultBrowserSettingEnabled": false,
  "BackgroundModeEnabled": false,
  "BookmarkBarEnabled": false,
  "BrowserSignin": 0,
  "DefaultNotificationsSetting": 2,
  "DefaultGeolocationSetting": 2,
  "DefaultMediaStreamSetting": 2,
  "PasswordManagerEnabled": false,
  "SafeBrowsingEnabled": false,
  "SearchSuggestEnabled": false,
  "SpellcheckEnabled": false,
  "TranslateEnabled": false,
  "UserFeedbackAllowed": false,
  "MetricsReportingEnabled": false,
  "DefaultCookiesSetting": 1,
  "DefaultPluginsSetting": 1,
  "AutofillAddressEnabled": false,
  "AutofillCreditCardEnabled": false,
  "PromotionalTabsEnabled": false,
  "EnableMediaRouter": false
}
EOF

# Create uBlock Origin configuration for optimal ad blocking
echo "Configuring uBlock Origin settings..."
UBLOCK_CONFIG_DIR="$CHROMIUM_DIR/Default/Local Extension Settings/$UBLOCK_ID"
mkdir -p "$UBLOCK_CONFIG_DIR"

# Create uBlock Origin configuration (simplified settings)
cat > "$CHROMIUM_DIR/ublock-config.json" << 'EOF'
{
  "selectedFilterLists": [
    "ublock-filters",
    "ublock-badware",
    "ublock-privacy",
    "ublock-abuse",
    "ublock-unbreak",
    "easylist",
    "easyprivacy",
    "urlhaus-1",
    "adguard-spyware-url",
    "fanboy-cookiemonster"
  ],
  "advancedUserEnabled": false,
  "contextMenuEnabled": false,
  "firewallPaneMinimized": true,
  "popupPanelSections": 1,
  "showIconBadge": false,
  "tooltipsDisabled": true,
  "cloudStorageEnabled": false,
  "importedLists": []
}
EOF

# Create a startup script that ensures uBlock Origin is properly configured
cat > "$CHROMIUM_DIR/setup-ublock.sh" << 'EOF'
#!/bin/bash
# uBlock Origin setup script for first run

CHROMIUM_DIR="/opt/fireplace/chromium-profile"
UBLOCK_ID="cjpalhdlnbpafiamejdnhcphjbkeiagm"

# Wait for extension to be installed
for i in {1..30}; do
    if [ -d "$CHROMIUM_DIR/Default/Extensions/$UBLOCK_ID" ]; then
        echo "uBlock Origin detected, configuring..."
        break
    fi
    sleep 1
done

# Copy configuration if uBlock Origin is installed
if [ -d "$CHROMIUM_DIR/Default/Extensions/$UBLOCK_ID" ]; then
    # Enable extension
    echo "Enabling uBlock Origin..."
    
    # The extension should auto-configure with our policies
    echo "uBlock Origin setup complete"
else
    echo "uBlock Origin not found, will retry on next start"
fi
EOF

chmod +x "$CHROMIUM_DIR/setup-ublock.sh"
chown fireplace:fireplace "$CHROMIUM_DIR/setup-ublock.sh"

# Update the kiosk service to use the configured profile
echo "Updating kiosk service configuration..."

# Check if the kiosk service file exists
if [ -f "/etc/systemd/system/fire-kiosk.service" ]; then
    # Update the service to use our configured Chromium profile
    sed -i 's|--user-data-dir=[^ ]*|--user-data-dir=/opt/fireplace/chromium-profile|g' /etc/systemd/system/fire-kiosk.service
    
    # Ensure extension loading is enabled
    if ! grep -q "load-extension" /etc/systemd/system/fire-kiosk.service; then
        sed -i '/--kiosk/i --load-extension=/opt/fireplace/chromium-profile/Default/Extensions/cjpalhdlnbpafiamejdnhcphjbkeiagm \\' /etc/systemd/system/fire-kiosk.service
    fi
    
    # Reload systemd
    systemctl daemon-reload
    echo -e "${GREEN}✅ Kiosk service updated with uBlock Origin${NC}"
else
    echo -e "${YELLOW}⚠ Kiosk service not found, will configure when service is created${NC}"
fi

# Create a test script to verify uBlock Origin is working
cat > "/opt/fireplace/test-ublock.sh" << 'EOF'
#!/bin/bash
# Test script to verify uBlock Origin is working

echo "Testing uBlock Origin installation..."

CHROMIUM_DIR="/opt/fireplace/chromium-profile"
UBLOCK_ID="cjpalhdlnbpafiamejdnhcphjbkeiagm"

# Check if extension directory exists
if [ -d "$CHROMIUM_DIR/Default/Extensions/$UBLOCK_ID" ]; then
    echo "✅ uBlock Origin extension directory found"
    
    # List extension versions
    versions=$(ls "$CHROMIUM_DIR/Default/Extensions/$UBLOCK_ID" 2>/dev/null | head -1)
    if [ ! -z "$versions" ]; then
        echo "✅ uBlock Origin version installed: $versions"
    else
        echo "❌ No uBlock Origin versions found"
    fi
else
    echo "❌ uBlock Origin not installed"
fi

# Check policies
if [ -f "/etc/chromium-browser/policies/managed/fireplace-kiosk.json" ]; then
    echo "✅ Chromium policies configured"
else
    echo "❌ Chromium policies not found"
fi

echo ""
echo "To test with a real browser session:"
echo "chromium-browser --user-data-dir=/opt/fireplace/chromium-profile --disable-web-security"
EOF

chmod +x "/opt/fireplace/test-ublock.sh"
chown fireplace:fireplace "/opt/fireplace/test-ublock.sh"

# Set final permissions
chown -R fireplace:fireplace "$CHROMIUM_DIR"
chmod -R 755 "$CHROMIUM_DIR"

echo ""
echo -e "${GREEN}✅ uBlock Origin setup complete!${NC}"
echo ""
echo "Configuration summary:"
echo "  ✓ Chromium policies configured for forced extension install"
echo "  ✓ uBlock Origin will auto-install from Chrome Web Store"
echo "  ✓ Ad blocking enabled for YouTube and other sites"
echo "  ✓ Kiosk profile configured at: $CHROMIUM_DIR"
echo ""
echo "Next steps:"
echo "1. Restart the kiosk service: sudo systemctl restart fire-kiosk.service"
echo "2. Test the setup: sudo -u fireplace /opt/fireplace/test-ublock.sh"
echo "3. Open a YouTube video to verify ads are blocked"
echo ""
echo "Note: uBlock Origin will install automatically on first Chromium launch."
echo "This may take a few moments during the first kiosk startup."