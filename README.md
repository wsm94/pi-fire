# Fireplace Pi 🔥

A Raspberry Pi kiosk system that displays fireplace videos with mobile control, automatic online/offline switching, and smooth transitions.

## Features

- **Full-screen fireplace display** - Chromium kiosk mode with YouTube or local videos
- **Mobile control** - Web interface accessible at `http://fireplace.local:8080`
- **Automatic failover** - Switches to offline mode when internet is down
- **YouTube integration** - Paste any YouTube URL or use presets
- **Local video support** - MP4, WebM, MKV, AVI, MOV files
- **Smooth transitions** - Cross-fade between videos
- **Volume control** - Adjustable volume and mute
- **State persistence** - Remembers settings across reboots

## Quick Start

### Development/Testing

1. **Clone and setup**:
   ```bash
   git clone <this-repo>
   cd pi-fire
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

2. **Run the control server**:
   ```bash
   python app/server.py
   ```

3. **Access the control interface**:
   Open `http://localhost:8080` in your browser

### Raspberry Pi Installation

1. **Install system**:
   ```bash
   sudo ./scripts/install.sh
   ```

2. **Enable services**:
   ```bash
   sudo ./scripts/enable.sh
   ```

3. **Add videos** (optional):
   ```bash
   sudo cp your-video.mp4 /opt/fireplace/videos/
   ```

4. **Access control**:
   Open `http://fireplace.local:8080` from any device on the same network

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