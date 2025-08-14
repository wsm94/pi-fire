# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Raspberry Pi fireplace kiosk project that creates a full-screen fireplace video display with mobile control. The system alternates between YouTube embeds and local video files, with automatic offline fallback when internet is unavailable.

## Architecture

The project follows a multi-component architecture as outlined in `docs/project-brief.md`:

### Core Components
- **Kiosk Player**: Chromium in full-screen kiosk mode displaying either YouTube embeds or local HTML player
- **Control Server**: Flask web app providing LAN-based control interface at `http://fireplace.local:8080`
- **Watcher Process**: Python daemon monitoring network connectivity and managing failover
- **State Management**: JSON-based persistence in `/opt/fireplace/state.json`

### Key Directories (planned structure)
```
app/
  server.py           # Main Flask control server
  watcher.py          # Network monitoring and failover logic
  validators.py       # Input validation and security
  upload_handler.py   # Video file upload management
  offline_player/     # Local HTML5 video player with playlist support
  templates/          # Flask HTML templates
  static/             # CSS/JS assets
systemd/              # Service files for auto-start
scripts/              # Installation and utility scripts
config/               # Configuration schemas and presets
tests/                # Unit tests for core functionality
```

## Development Commands

Since this is an early-stage project with only documentation, there are no build/test commands yet. When implementing:

- **Installation**: `./scripts/install.sh` (creates systemd services and installs dependencies)
- **Testing**: Python unittest framework for `tests/test_*.py` files
- **Deployment**: systemd services `fire-web.service` and `fire-kiosk.service`

## Key Technical Details

### State File Schema
The system persists state in `/opt/fireplace/state.json` with fields for:
- Current mode (online/offline)
- Last YouTube URL and selected offline video
- Volume, mute status, and display settings
- Custom playlists and active playlist selection

### Network Monitoring
Implements exponential backoff (5s → 60s) when checking connectivity against multiple endpoints:
- Google generate_204
- Cloudflare 1.1.1.1
- Google 8.8.8.8

### Security Features
- Flask-Login session management
- Rate limiting on API endpoints
- Input validation with regex and JSON Schema
- Optional HTTPS with self-signed certificates

### Video Support
- Local videos in `/opt/fireplace/videos/` supporting `.mp4`, `.webm`, `.mkv`, `.avi`, `.mov`
- Gapless playbook with two-video buffer system
- Automatic thumbnail generation using ffmpeg

## Installation Target

Raspberry Pi OS (Bookworm) 64-bit with:
- Chromium with uBlock Origin for ad blocking
- Python 3 + Flask for web control
- systemd for process management
- avahi-daemon for mDNS (fireplace.local)

## Development Notes

- This is a kiosk application prioritizing reliability and automatic recovery
- All user inputs require validation to prevent path traversal and injection attacks  
- The system must gracefully handle network outages and Chromium crashes
- Wi-Fi pre-provisioning supports plug-and-play deployment