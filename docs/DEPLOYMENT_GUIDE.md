# 🔥 Fireplace Pi - Deployment Guide

This guide covers deploying the Fireplace Pi system to a new Raspberry Pi, including Wi-Fi pre-provisioning for headless setup.

## Prerequisites

- Raspberry Pi 5 (or Pi 4)
- MicroSD card (16GB or larger)
- Raspberry Pi OS image (64-bit recommended)
- Computer with SD card reader
- Target Wi-Fi network credentials

## Method 1: Pre-provisioned SD Card (Recommended)

This method configures everything before first boot, perfect for remote deployment.

### Step 1: Flash Raspberry Pi OS

1. Download [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
2. Flash Raspberry Pi OS (64-bit) to your SD card
3. **Don't remove the SD card yet!**

### Step 2: Pre-provision the SD Card

On your computer with the SD card still inserted:

```bash
# Clone the repository (if not already done)
git clone https://github.com/your-username/pi-fire.git
cd pi-fire

# Run the pre-provisioning script
sudo ./scripts/preprovision_sd_card.sh
```

The script will:
- Enable SSH for remote access
- Configure Wi-Fi network(s)
- Set the hostname (default: fireplace)
- Optionally create auto-installation script

### Step 3: First Boot

1. Insert SD card into Raspberry Pi
2. Connect power (Pi will boot automatically)
3. Wait 2-3 minutes for initial boot
4. Connect via SSH:
   ```bash
   ssh pi@fireplace.local
   # Default password: raspberry (change it!)
   ```

### Step 4: Install Fireplace Pi

If auto-installation was configured, it will run automatically. Otherwise:

```bash
# Change default password first!
passwd

# Clone and install Fireplace Pi
git clone https://github.com/your-username/pi-fire.git
cd pi-fire
sudo ./scripts/install.sh
sudo ./scripts/enable.sh
sudo ./scripts/configure_power_management.sh
sudo ./scripts/setup_sudoers.sh
sudo ./scripts/setup_scheduled_shutdown.sh
```

## Method 2: Manual Wi-Fi Configuration

If the Pi is already running, use the Wi-Fi configuration tool:

```bash
sudo ./scripts/configure_wifi.sh
```

This interactive tool allows you to:
- Add multiple Wi-Fi networks
- Set network priorities
- Test connectivity
- Create deployment configurations

### Quick Mode

For adding a single network quickly:

```bash
sudo ./scripts/configure_wifi.sh --quick
```

## Method 3: Raspberry Pi Imager Settings

When using Raspberry Pi Imager, you can pre-configure:

1. Click the gear icon (⚙️) for advanced options
2. Set:
   - **Hostname**: fireplace
   - **Enable SSH**: Yes (use password authentication)
   - **Username/Password**: pi / [your-password]
   - **Configure Wi-Fi**: Yes
     - SSID: [your-network-name]
     - Password: [your-network-password]
     - Country: [your-country-code]
   - **Locale Settings**: Set your timezone

## Post-Deployment Configuration

### 1. Access the Web Interface

Once installed, access the control interface:
```
http://fireplace.local:8080
```

Or use the IP address if mDNS isn't working:
```bash
ip addr show wlan0
# Look for inet address
```

### 2. Configure Settings

In the web interface:

1. **Upload Videos**: Place `.mp4` files in `/opt/fireplace/videos/`
2. **Set Favorites**: Play a video and click "⭐ Add to Favorites"
3. **Schedule Shutdown**: Hamburger menu → Scheduled Shutdown
4. **Test Modes**: Switch between Online (YouTube) and Offline modes

### 3. Power Management

The Pi 5 is configured for minimal standby power (3-4mA when shutdown).

**Safe shutdown options:**
- Web interface: ☰ → Shutdown System
- SSH: `sudo shutdown -h now`
- Physical: Simply switch off power (though proper shutdown is preferred)

**Auto-boot**: The Pi will automatically boot when power is applied.

## Deployment Checklist

### Pre-deployment
- [ ] SD card flashed with Raspberry Pi OS
- [ ] Wi-Fi credentials configured
- [ ] SSH enabled
- [ ] Hostname set (fireplace)
- [ ] Auto-installation script created (optional)

### First Boot
- [ ] Pi connected to network
- [ ] SSH access working
- [ ] Default password changed
- [ ] Fireplace Pi software installed
- [ ] Services enabled and running

### Configuration
- [ ] Web interface accessible
- [ ] Test videos uploaded
- [ ] Favorites configured
- [ ] Scheduled shutdown set (if desired)
- [ ] Kiosk mode tested

### Final Deployment
- [ ] Pi positioned at final location
- [ ] Display connected and working
- [ ] Network connection stable
- [ ] Auto-start on power confirmed
- [ ] Remote control tested from phone/laptop

## Troubleshooting

### Can't connect to fireplace.local

1. Try the IP address instead:
   ```bash
   # On the Pi (via keyboard or SSH with IP)
   ip addr show wlan0
   ```

2. Check if mDNS is working:
   ```bash
   sudo systemctl status avahi-daemon
   ```

### Web interface not accessible

1. Check if service is running:
   ```bash
   sudo systemctl status fire-web.service
   ```

2. Check logs:
   ```bash
   sudo journalctl -u fire-web.service -f
   ```

### Wi-Fi not connecting

1. Check configuration:
   ```bash
   # For NetworkManager
   nmcli con show
   
   # For wpa_supplicant
   sudo cat /etc/wpa_supplicant/wpa_supplicant.conf
   ```

2. Reconfigure Wi-Fi:
   ```bash
   sudo ~/pi-fire/scripts/configure_wifi.sh
   ```

### Videos not playing

1. Check video format (MP4 recommended)
2. Verify files exist:
   ```bash
   ls -la /opt/fireplace/videos/
   ```
3. Check permissions:
   ```bash
   sudo chown -R fireplace:fireplace /opt/fireplace/videos/
   ```

## Security Considerations

1. **Change default password immediately**
2. **Use strong Wi-Fi passwords**
3. **Consider firewall rules if exposed to public network**
4. **Regular updates**: `sudo apt update && sudo apt upgrade`

## Support

For issues or questions:
- Check logs: `/var/log/fireplace/`
- Service status: `sudo systemctl status fire-*.service`
- GitHub Issues: [your-repo-url]/issues