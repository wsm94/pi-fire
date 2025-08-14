# Project Brief: Fireplace Pi — Online/Offline Fireplace with Mobile Control

## Goal

A Raspberry Pi 5 boots into a full-screen "fireplace" video. From my phone (same Wi-Fi), I can paste a YouTube URL or tap a preset to switch fires. If there's no internet, it automatically falls back to looping a local playlist of pre-downloaded fires. Make a best-effort to block/avoid YouTube ads. Support pre-provisioned Wi-Fi so the unit is plug-and-play at the install location.

## Hardware (given)

- Raspberry Pi 5 (4 GB), official 5 V/5 A USB-C PSU recommended
- HDMI display (Pi micro-HDMI → display HDMI/mini-HDMI)

## Architecture

### Kiosk player
Chromium in full-screen kiosk, pointed at either:
- an online YouTube embed, or
- a local offline HTML player that loops videos in `/opt/fireplace/videos`.

### Control server
Flask app on LAN (same Wi-Fi) to:
- set/get current source URL,
- switch between "YouTube" and "Offline" modes,
- trigger reload, toggle sound, control volume, screen on/off, and choose among local files.
- **Enhanced**: Upload videos through web UI, manage playlists, view system status

### State
`/opt/fireplace/state.json` (stores last URL, mode, volume, mute, selected offline video, etc.).
- **Enhanced**: Schema validation, automatic backups, migration support

### Watcher
Python process that:
- launches Chromium with the right target,
- monitors network reachability with multiple endpoints and exponential backoff,
- auto-fails over to offline when internet is down and auto-restores online when back.
- **Enhanced**: Memory usage monitoring, frozen video detection, log rotation

### Ad handling
Install and pre-configure uBlock Origin in Chromium profile; optionally support a configurable privacy frontend (e.g., Invidious/Piped) to proxy YouTube embeds as a fallback path.

### Security
- **Enhanced**: Rate limiting on API endpoints, optional HTTPS with self-signed cert, Flask-Login sessions, input validation for all user inputs

### Autostart
Two systemd services (`fire-web.service`, `fire-kiosk.service`), restart-on-failure with resource limits.

### mDNS
http://fireplace.local:8080

## Non-Goals / Notes

- No cloud accounts; LAN-only control.
- YouTube ads: full suppression is not guaranteed (server-side ads exist). We'll do best-effort via uBlock + optional frontend, and provide an Offline mode that avoids ads entirely. (YouTube Premium on a dedicated account is another reliable option.)
- We will not download YouTube videos automatically. Provide a `/opt/fireplace/videos/` folder for user-supplied files (e.g., from licensed stock video).

## Functional Requirements

### Boot experience
- Within ~20–30s post-login, display either last used Online URL (YouTube embed) or Offline local video loop.
- **Enhanced**: Show loading spinner during mode changes, optional status overlay

### Offline fallback
- Detect loss of internet using multiple endpoints (Google generate_204, 1.1.1.1, 8.8.8.8) with 1-2s timeout
- Implement exponential backoff (5s → 10s → 30s → 60s) to reduce CPU usage when offline
- If offline while in Online mode → smooth fade transition to Offline local playlist
- When internet returns → switch back to previous Online URL automatically (configurable "stick to offline until manual switch" flag)

### Local videos
- Folder: `/opt/fireplace/videos/*` supporting multiple formats: `.mp4`, `.webm`, `.mkv`, `.avi`, `.mov`
- Include a sophisticated offline player page (`/opt/fireplace/offline.html`) that:
  - lists available files with thumbnails, sizes, and durations
  - loops selected file, or cycles through a playlist with cross-fade
  - implements two-video buffer system for gapless playback
  - hides cursor (unclutter) and shows no controls
  - supports creating and saving custom playlists

### Control page (LAN only)
- Shows current mode (Online/Offline), current URL or selected local file
- Input to paste a new YouTube URL with regex validation
- Preset buttons for common fires
- Buttons: Save/Reload, Mute toggle, Volume slider (0-100 validated), Screen Off/On (with CEC support), Mode switch
- **Enhanced**: File upload interface, playlist management, system health display (CPU temp, storage), thumbnail previews

### Ad handling (best-effort)
- Pre-install uBlock Origin into dedicated Chromium profile
- Optional: support YOUTUBE_FRONTEND_BASE configuration
- Cache YouTube embed pages locally when possible

### Wi-Fi pre-provisioning
- Support dropping a `wpa_supplicant.conf` or `fireplace-wifi.conf` into boot partition
- Allow multiple SSIDs with priorities; ensure country= is set
- **Enhanced**: First-run wizard for network testing and configuration

### Persistence
- All settings persist in `/opt/fireplace/state.json` with schema validation
- Automatic backup of last known good state
- Configuration export/import endpoints

### Resilience
- Chromium auto-restarts on crash with memory usage monitoring
- Screenshot comparison for frozen video detection
- If state is corrupt, restore from backup or fall back to Offline
- Network interface recovery for extended connection loss

## Tech Choices

- **OS**: Raspberry Pi OS (Bookworm) 64-bit
- **Browser**: Chromium with dedicated profile
- **Server**: Python 3 + Flask + Flask-Login
- **Process**: systemd with resource limits
- **mDNS**: avahi-daemon
- **Audio**: amixer control (ALSA)
- **Network check**: Python requests with redundant endpoints
- **Display**: vcgencmd + CEC control
- **Validation**: JSON Schema, regex for URLs

## Repo Layout

```
fireplace-pi/
  app/
    server.py
    watcher.py
    validators.py
    upload_handler.py
    offline_player/
      offline.html
      offline.js
      offline.css
    templates/
      index.html
      setup_wizard.html
    static/
      main.css
      main.js
  systemd/
    fire-web.service
    fire-kiosk.service
  scripts/
    install.sh
    enable.sh
    chromium-launch.sh
    install-ublock.sh
    generate-thumbnails.sh
    backup-restore.sh
  config/
    presets.json
    policy.json
    schema.json
  assets/
    sample_readme_for_videos.md
    troubleshooting.md
    quick_start_card.pdf
  tests/
    test_validators.py
    test_network.py
  README.md
```

## Key Implementation Details

### 1) State file

`/opt/fireplace/state.json` (created on first run with schema validation)

```json
{
  "mode": "online",
  "last_online_url": "https://www.youtube.com/watch?v=XXXX",
  "selected_offline": "campfire.mp4",
  "volume": 60,
  "muted": true,
  "stick_offline_until_manual": false,
  "playlists": {
    "default": ["campfire.mp4", "fireplace.mp4"],
    "custom1": ["video1.mp4", "video2.mp4"]
  },
  "active_playlist": "default",
  "show_status_overlay": false,
  "version": "1.0"
}
```

### 2) Configuration file

`/opt/fireplace/config/policy.json`

```json
{
  "network": {
    "check_interval": 5,
    "check_timeout": 2,
    "check_endpoints": [
      "https://clients3.google.com/generate_204",
      "https://1.1.1.1/",
      "https://8.8.8.8/"
    ],
    "exponential_backoff": true,
    "max_backoff": 60,
    "stick_to_offline_until_manual": false
  },
  "display": {
    "idle_dim_minutes": 0,
    "screensaver_disabled": true,
    "cec_enabled": true,
    "show_clock": false
  },
  "youtube": {
    "frontend_base": null,
    "quality_preference": "1080p",
    "cache_embeds": true
  },
  "security": {
    "pin_required": true,
    "https_enabled": false,
    "rate_limit_per_minute": 60
  },
  "system": {
    "max_chromium_memory_mb": 1024,
    "log_rotation_days": 7,
    "thumbnail_generation": true
  }
}
```

### 3) Building YouTube embeds

Convert watch/short URLs to embed form with validation:
```
https://www.youtube.com/embed/<ID>?autoplay=1&controls=0&rel=0&mute=1&loop=1&playlist=<ID>&modestbranding=1
```

If YOUTUBE_FRONTEND_BASE is set, use:
```
<BASE>/embed/<ID>?autoplay=1&controls=0&loop=1
```

### 4) Offline player enhancements

- Implement video preloading with two-video buffer
- Cross-fade transitions using CSS opacity
- Playlist management with drag-and-drop reordering
- Thumbnail display using generated previews
- File size and duration metadata display

### 5) Watcher logic enhancements

```python
# Pseudo-code additions
class EnhancedWatcher:
    def __init__(self):
        self.backoff_time = 5
        self.memory_threshold_mb = 1024
        
    def check_network_with_backoff(self):
        # Try multiple endpoints
        # Implement exponential backoff
        
    def monitor_chromium_health(self):
        # Check memory usage
        # Detect frozen video via screenshots
        # Restart if unhealthy
        
    def smooth_transition(self, new_target):
        # Fade out current
        # Switch target
        # Fade in new
```

### 6) Security implementation

- Flask-Login for session management
- Rate limiting with Flask-Limiter
- Input validation using regex and JSON Schema
- Path traversal protection for file operations
- Optional HTTPS with self-signed certificate generation

### 7) Control API enhancements

- `GET /` → enhanced control UI with status dashboard
- `POST /api/upload` → video file upload with progress
- `GET /api/thumbnails/<video>` → generated video thumbnails
- `POST /api/playlist` → create/update playlists
- `GET /api/system/health` → CPU temp, memory, storage
- `POST /api/config/export` → download full configuration
- `POST /api/config/import` → restore configuration
- All POST endpoints protected by rate limiting and authentication

### 8) Install script additions

```bash
# Additional packages
apt install:
  - ffmpeg (for thumbnail generation)
  - python3-pil (for image processing)
  - flask-login flask-limiter
  - cec-utils (for TV control)

# Profile setup
- Create dedicated Chromium profile directory
- Configure to disable update notifications
- Pre-seed uBlock filters

# First-run setup
- Generate self-signed cert if HTTPS enabled
- Create thumbnail cache directory
- Initialize backup directory
```

### 9) Chromium launch flags (enhanced)

```bash
chromium-browser \
  --kiosk \
  --noerrdialogs \
  --disable-session-crashed-bubble \
  --disable-infobars \
  --autoplay-policy=no-user-gesture-required \
  --start-fullscreen \
  --overscroll-history-navigation=0 \
  --incognito \
  --load-extension=/opt/ublock \
  --user-data-dir=/opt/fireplace/chromium-profile \
  --disable-features=TranslateUI \
  --disable-component-update \
  --disable-background-timer-throttling \
  "<TARGET_URL_OR_FILE>"
```

### 10) Video format support

```python
SUPPORTED_FORMATS = ['.mp4', '.webm', '.mkv', '.avi', '.mov']
MAX_UPLOAD_SIZE_MB = 2048
THUMBNAIL_SIZE = (320, 180)
```

## Acceptance Criteria

### Core Functionality
- Boots into last mode within ~30s and stays full-screen
- Smooth transitions between online/offline modes
- If internet drops, switches to Offline within ≤5s with fade effect
- Control UI accessible at http://fireplace.local:8080 with authentication
- uBlock Origin active for Online mode
- Offline mode plays local files smoothly with gapless playback

### Enhanced Features
- Video upload through web interface works reliably
- Thumbnails generated for all videos
- System health monitoring available
- Configuration backup/restore functional
- Input validation prevents malicious inputs
- Rate limiting prevents API abuse
- Memory usage stays within limits

### Network & Setup
- Wi-Fi pre-provisioning works on first boot
- Multiple network endpoints provide redundancy
- Exponential backoff reduces resource usage
- First-run wizard simplifies setup

## Documentation

### Quick Start Card
- Default URL: http://fireplace.local:8080
- Default PIN: (set during installation)
- Adding videos: Upload through web UI or copy to `/opt/fireplace/videos/`
- Factory reset: `sudo /opt/fireplace/scripts/backup-restore.sh --reset`

### Troubleshooting Guide
- Black screen: Check HDMI connection, verify Chromium process
- Network issues: Check `/var/log/fireplace/network.log`
- Videos not playing: Verify format, check permissions
- High CPU usage: Review memory limits, check for frozen video

## Stretch Goals

- Scheduled quiet hours with configurable schedule
- Advanced cross-fade with configurable duration
- Theme selection for control UI
- Mobile app for iOS/Android
- Integration with home automation systems
- Multi-zone support (control multiple Pis)
- Weather/time overlay options
- Ambient sound support