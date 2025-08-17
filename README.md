# 🔥 Fireplace Pi

Transform your Raspberry Pi into a beautiful, remotely-controlled fireplace display with automatic YouTube and offline video playback, ad blocking, and smart power management.

## ✨ Features

- 🔥 **Dual Mode Display**: YouTube videos online, local MP4s offline with automatic failover
- 📱 **Mobile Control**: Full web interface accessible from any device on your network
- ⭐ **Favorites System**: Save and quickly access your preferred fireplace videos
- 🚫 **Ad-free Experience**: Built-in uBlock Origin blocks YouTube ads automatically
- ⏰ **Scheduled Shutdown**: Automatic daily shutdown (default 2 AM, configurable)
- 🔌 **Smart Power Management**: Minimal standby power, auto-boot on power restore
- 🌐 **Easy Deployment**: Wi-Fi pre-provisioning for headless setup
- 🎯 **Kiosk Mode**: Fullscreen display with auto-recovery and remote control

## 🚀 Quick Setup

### Method 1: One-Command Install (Recommended)

```bash
# Clone and install everything automatically
git clone https://github.com/your-username/pi-fire.git
cd pi-fire
sudo ./scripts/full_setup.sh
```

This installs everything: dependencies, services, ad blocking, power management, and more!

### Method 2: Manual Installation

```bash
# Clone repository
git clone https://github.com/your-username/pi-fire.git
cd pi-fire

# Install core system
sudo ./scripts/install.sh

# Enable services and configure features
sudo ./scripts/enable.sh
sudo ./scripts/setup_sudoers.sh
sudo ./scripts/setup_scheduled_shutdown.sh
sudo ./scripts/setup_ublock_origin.sh
```

### Method 3: Pre-provisioned SD Card

For headless deployment, pre-configure an SD card with Wi-Fi:

```bash
# On your computer with SD card inserted
sudo ./scripts/preprovision_sd_card.sh
```

## 📱 Web Interface

Access the control interface at:
- `http://fireplace.local:8080` (mDNS)
- `http://[pi-ip-address]:8080` (direct IP)

### Main Features:
- **Mode Toggle**: Switch between YouTube and offline videos
- **YouTube Control**: Paste any YouTube fireplace video URL
- **Video Library**: Select from local MP4 files
- **Favorites**: ⭐ Save current video for quick access
- **Volume Control**: Adjust audio levels
- **Power Menu**: ☰ Shutdown, reboot, schedule settings

## 🎬 Adding Videos

### Local Videos (Offline Mode)
```bash
# Copy MP4 files to the videos directory
sudo cp your-fireplace-video.mp4 /opt/fireplace/videos/
sudo chown fireplace:fireplace /opt/fireplace/videos/*.mp4
```

### YouTube Videos (Online Mode)
1. Find a fireplace video on YouTube
2. Copy the URL
3. Paste it in the web interface
4. Click ⭐ to save as favorite

**Recommended Sources:**
- [Archive.org Fireplace Collection](https://archive.org/search.php?query=fireplace)
- YouTube searches: "fireplace 4k", "crackling fire", "cozy fireplace"

## ⚙️ Configuration

### Scheduled Shutdown
- Access via ☰ → Scheduled Shutdown
- Default: 2:00 AM daily
- Options: Weekdays only, custom time

### Wi-Fi Networks
```bash
# Add/configure networks for deployment
sudo ./scripts/configure_wifi.sh
```

### Power Management
- **Auto-boot**: Pi automatically starts when power applied
- **Safe shutdown**: Use web interface or `sudo shutdown -h now`
- **Minimal standby**: 3-4mA power draw when shutdown

### Kiosk Controls
```bash
# Start/stop fullscreen display
sudo systemctl start fire-kiosk.service
sudo systemctl stop fire-kiosk.service

# Or use web interface: ☰ → Start/Stop Kiosk
```

## 🛠️ Hardware Setup

### Recommended Hardware
- **Raspberry Pi 5** (or Pi 4 4GB+)
- **MicroSD Card**: 16GB+ Class 10
- **Display**: HDMI monitor/TV
- **Power**: Official Pi power supply
- **Case**: Optional, with good ventilation

### Display Connection
1. Connect Pi to display via HDMI
2. Power on Pi (auto-boots to desktop)
3. Kiosk mode goes fullscreen automatically

## 🚨 Troubleshooting

### Can't Access Web Interface
```bash
# Check service status
sudo systemctl status fire-web.service

# Try IP address instead of hostname
ip addr show wlan0
```

### No Video Playback
```bash
# Check video files
ls -la /opt/fireplace/videos/

# Verify permissions
sudo chown -R fireplace:fireplace /opt/fireplace/videos/
```

### Kiosk Not Starting
```bash
# Check kiosk service
sudo systemctl status fire-kiosk.service

# View logs
sudo journalctl -u fire-kiosk.service -f
```

### Network Issues
```bash
# Reconfigure Wi-Fi
sudo ./scripts/configure_wifi.sh

# Check network status
nmcli con show
```

## 📚 Documentation

- [Deployment Guide](docs/DEPLOYMENT_GUIDE.md) - Detailed setup instructions
- [Project Brief](docs/project-brief.md) - Technical architecture

## 🔧 Development

```bash
# Development mode
cd /opt/fireplace
source venv/bin/activate
python app/server.py

# Run tests
python tests/test_basic.py
```

## Architecture

### Components

- **Flask Control Server** (`app/server.py`) - Web API and control interface
- **Watcher Process** (`app/watcher.py`) - Network monitoring and Chromium management  
- **Offline Player** (`app/offline_player/`) - HTML5 video player with playlist support
- **Configuration** (`config/`) - JSON schemas, defaults, and presets

### Files

```
/opt/fireplace/
├── state.json          # Current settings (mode, volume, selected video)
├── config/
│   ├── policy.json     # System configuration  
│   └── presets.json    # YouTube preset buttons
├── videos/             # Local video files
└── app/                # Application code
```

## API Endpoints

- `GET /` - Control interface
- `GET /api/state` - Current system state
- `POST /api/mode` - Switch between online/offline
- `POST /api/url` - Set YouTube URL
- `POST /api/preset` - Load preset YouTube URL
- `POST /api/volume` - Set volume (0-100)
- `POST /api/mute` - Toggle mute
- `POST /api/offline-video` - Select offline video
- `GET /api/videos` - List available videos

## Configuration

### State File (`/opt/fireplace/state.json`)
```json
{
  "mode": "online|offline",
  "last_online_url": "YouTube URL",
  "selected_offline": "video.mp4", 
  "volume": 60,
  "muted": true,
  "playlists": {
    "default": ["video1.mp4", "video2.mp4"]
  }
}
```

### Policy File (`/opt/fireplace/config/policy.json`)
```json
{
  "network": {
    "check_interval": 5,
    "check_endpoints": ["https://8.8.8.8/", "https://1.1.1.1/"]
  },
  "youtube": {
    "frontend_base": null
  }
}
```

## Development

### Running Components Separately

1. **Control server only**:
   ```bash
   cd app && python server.py
   ```

2. **Watcher only** (requires control server running):
   ```bash
   cd app && python watcher.py  
   ```

3. **Offline player only**:
   ```bash
   # Access http://localhost:8080/offline after starting server
   ```

### Testing

- **Control interface**: `http://localhost:8080`
- **Offline player**: `http://localhost:8080/offline`  
- **API state**: `curl http://localhost:8080/api/state`

### Development Notes

- State and config files will fallback to `config/` directory during development
- Videos should be placed in `/opt/fireplace/videos/` or create symlink for testing
- Chromium kiosk mode requires X11/display server

## Troubleshooting

### Common Issues

1. **Control interface not accessible**:
   - Check `sudo systemctl status fire-web.service`
   - Verify port 8080 is not blocked

2. **Chromium won't start**:
   - Check `sudo journalctl -u fire-kiosk.service -f`  
   - Ensure X11 is running and accessible

3. **Videos not playing**:
   - Check video file permissions in `/opt/fireplace/videos/`
   - Verify supported format (MP4, WebM, MKV, AVI, MOV)

4. **Network switching not working**:
   - Check internet connectivity
   - Review network check endpoints in policy.json

### Logs

```bash
# Web server logs
sudo journalctl -u fire-web.service -f

# Kiosk watcher logs  
sudo journalctl -u fire-kiosk.service -f

# All fireplace logs
sudo journalctl -u fire-* -f
```

## Hardware Requirements

- Raspberry Pi 5 (4GB recommended)
- HDMI display
- Network connection (WiFi or Ethernet)
- Storage for video files (8GB+ recommended)

## License

MIT License - see project brief for full details.