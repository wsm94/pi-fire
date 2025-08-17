#!/usr/bin/env python3

import json
import os
from pathlib import Path
from flask import Flask, render_template, request, jsonify, send_from_directory
import logging
from typing import Dict, Any, Optional
import shutil

try:
    # Try relative import first (when run as module)
    from .validators import ConfigValidator, URLValidator, FileValidator, validate_volume, validate_mode, FavoritesValidator
except ImportError:
    # Fall back to direct import (when run as script)
    from validators import ConfigValidator, URLValidator, FileValidator, validate_volume, validate_mode, FavoritesValidator

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.secret_key = os.environ.get('FLASK_SECRET_KEY', 'dev-key-change-in-production')

STATE_FILE = "/opt/fireplace/state.json"
POLICY_FILE = "/opt/fireplace/config/policy.json"
PRESETS_FILE = "/opt/fireplace/config/presets.json"
VIDEOS_DIR = "/opt/fireplace/videos"

STATE_FILE_DEV = Path(__file__).parent.parent / "config" / "state_default.json"
POLICY_FILE_DEV = Path(__file__).parent.parent / "config" / "policy.json"
PRESETS_FILE_DEV = Path(__file__).parent.parent / "config" / "presets.json"

validator = ConfigValidator()

class StateManager:
    def __init__(self):
        self.state_file = STATE_FILE if os.path.exists(STATE_FILE) else STATE_FILE_DEV
        self._current_state = None
    
    def load_state(self) -> Dict[str, Any]:
        if self._current_state is None:
            try:
                with open(self.state_file, 'r') as f:
                    self._current_state = json.load(f)
                    
                if not validator.validate_state(self._current_state):
                    logger.warning("State validation failed, using defaults")
                    self._current_state = self._load_default_state()
                    
            except (FileNotFoundError, json.JSONDecodeError) as e:
                logger.warning(f"Could not load state: {e}, using defaults")
                self._current_state = self._load_default_state()
        
        return self._current_state
    
    def save_state(self, state: Dict[str, Any]) -> bool:
        if not validator.validate_state(state):
            logger.error("State validation failed, not saving")
            return False
        
        try:
            os.makedirs(os.path.dirname(self.state_file), exist_ok=True)
            with open(self.state_file, 'w') as f:
                json.dump(state, f, indent=2)
            self._current_state = state.copy()
            logger.info("State saved successfully")
            return True
        except Exception as e:
            logger.error(f"Failed to save state: {e}")
            return False
    
    def _load_default_state(self) -> Dict[str, Any]:
        try:
            with open(STATE_FILE_DEV, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Could not load default state: {e}")
            return {
                "mode": "offline",
                "volume": 60,
                "muted": True,
                "version": "1.0"
            }
    
    def update_field(self, field: str, value: Any) -> bool:
        state = self.load_state()
        state[field] = value
        return self.save_state(state)

state_manager = StateManager()

def load_policy() -> Dict[str, Any]:
    policy_file = POLICY_FILE if os.path.exists(POLICY_FILE) else POLICY_FILE_DEV
    try:
        with open(policy_file, 'r') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Could not load policy: {e}")
        return {"network": {"check_interval": 5, "check_timeout": 2, "check_endpoints": ["https://8.8.8.8/"]}}

def load_presets() -> Dict[str, Any]:
    presets_file = PRESETS_FILE if os.path.exists(PRESETS_FILE) else PRESETS_FILE_DEV
    try:
        with open(presets_file, 'r') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Could not load presets: {e}")
        return {"presets": []}

def get_available_videos() -> list:
    videos_dir = Path(VIDEOS_DIR)
    if not videos_dir.exists():
        return []
    
    videos = []
    for video_file in videos_dir.iterdir():
        if video_file.is_file() and FileValidator.is_supported_video(video_file.name):
            videos.append({
                "filename": video_file.name,
                "size": video_file.stat().st_size,
                "path": str(video_file)
            })
    
    return sorted(videos, key=lambda x: x["filename"])

@app.route('/')
def index():
    state = state_manager.load_state()
    policy = load_policy()
    presets = load_presets()
    videos = get_available_videos()
    favorites = state.get('user_favorites', [])
    
    return render_template('index.html', 
                         state=state,
                         policy=policy,
                         presets=presets["presets"],
                         videos=videos,
                         favorites=favorites)

@app.route('/api/state', methods=['GET'])
def get_state():
    return jsonify(state_manager.load_state())

@app.route('/api/mode', methods=['POST'])
def set_mode():
    data = request.get_json()
    if not data or 'mode' not in data:
        return jsonify({"error": "Mode required"}), 400
    
    mode = validate_mode(data['mode'])
    if mode is None:
        return jsonify({"error": "Invalid mode"}), 400
    
    if state_manager.update_field('mode', mode):
        logger.info(f"Mode changed to {mode}")
        return jsonify({"success": True, "mode": mode})
    
    return jsonify({"error": "Failed to save mode"}), 500

@app.route('/api/url', methods=['POST'])
def set_url():
    data = request.get_json()
    if not data or 'url' not in data:
        return jsonify({"error": "URL required"}), 400
    
    url = data['url'].strip()
    if not URLValidator.is_valid_youtube_url(url):
        return jsonify({"error": "Invalid YouTube URL"}), 400
    
    if state_manager.update_field('last_online_url', url):
        embed_url = URLValidator.build_youtube_embed(url)
        logger.info(f"URL changed to {url}")
        return jsonify({"success": True, "url": url, "embed_url": embed_url})
    
    return jsonify({"error": "Failed to save URL"}), 500

@app.route('/api/preset', methods=['POST'])
def set_preset():
    data = request.get_json()
    if not data or 'url' not in data:
        return jsonify({"error": "Preset URL required"}), 400
    
    url = data['url'].strip()
    if not URLValidator.is_valid_youtube_url(url):
        return jsonify({"error": "Invalid preset YouTube URL"}), 400
    
    success = state_manager.update_field('last_online_url', url)
    if success and state_manager.load_state().get('mode') != 'online':
        success = state_manager.update_field('mode', 'online')
    
    if success:
        embed_url = URLValidator.build_youtube_embed(url)
        logger.info(f"Preset selected: {url}")
        return jsonify({"success": True, "url": url, "embed_url": embed_url, "mode": "online"})
    
    return jsonify({"error": "Failed to set preset"}), 500

@app.route('/api/volume', methods=['GET', 'POST'])
def handle_volume():
    if request.method == 'GET':
        state = state_manager.load_state()
        return jsonify({"volume": state.get("volume", 60)})
    
    data = request.get_json()
    if not data or 'volume' not in data:
        return jsonify({"error": "Volume required"}), 400
    
    volume = validate_volume(data['volume'])
    if volume is None:
        return jsonify({"error": "Volume must be 0-100"}), 400
    
    if state_manager.update_field('volume', volume):
        logger.info(f"Volume changed to {volume}")
        return jsonify({"success": True, "volume": volume})
    
    return jsonify({"error": "Failed to save volume"}), 500

@app.route('/api/mute', methods=['POST'])
def toggle_mute():
    data = request.get_json()
    if not data or 'muted' not in data:
        return jsonify({"error": "Muted state required"}), 400
    
    muted = bool(data['muted'])
    
    if state_manager.update_field('muted', muted):
        logger.info(f"Mute changed to {muted}")
        return jsonify({"success": True, "muted": muted})
    
    return jsonify({"error": "Failed to save mute state"}), 500

@app.route('/api/offline-video', methods=['POST'])
def set_offline_video():
    data = request.get_json()
    if not data or 'filename' not in data:
        return jsonify({"error": "Filename required"}), 400
    
    filename = data['filename']
    videos = get_available_videos()
    
    if not any(v['filename'] == filename for v in videos):
        return jsonify({"error": "Video not found"}), 404
    
    if state_manager.update_field('selected_offline', filename):
        logger.info(f"Selected offline video: {filename}")
        return jsonify({"success": True, "filename": filename})
    
    return jsonify({"error": "Failed to save offline video selection"}), 500

@app.route('/api/videos', methods=['GET'])
def list_videos():
    return jsonify({"videos": get_available_videos()})

@app.route('/api/favorites', methods=['GET'])
def get_favorites():
    """Get all user favorites"""
    state = state_manager.load_state()
    favorites = state.get('user_favorites', [])
    return jsonify({"favorites": favorites})

@app.route('/api/favorites/add', methods=['POST'])
def add_favorite():
    """Add current playing content to favorites"""
    data = request.get_json()
    if not data or 'name' not in data:
        return jsonify({"error": "Favorite name required"}), 400
    
    name = data['name']
    state = state_manager.load_state()
    current_mode = state.get('mode')
    
    # Get current favorites to check for duplicates
    current_favorites = state.get('user_favorites', [])
    
    # Create favorite based on current mode
    favorite = None
    if current_mode == 'online':
        current_url = state.get('last_online_url')
        if not current_url:
            return jsonify({"error": "No online URL currently set"}), 400
        
        # Check for duplicate
        if FavoritesValidator.find_duplicate_favorite(current_favorites, url=current_url):
            return jsonify({"error": "This video is already in favorites"}), 400
        
        favorite = FavoritesValidator.create_favorite_from_online(name, current_url)
    
    elif current_mode == 'offline':
        current_filename = state.get('selected_offline')
        if not current_filename:
            return jsonify({"error": "No offline video currently selected"}), 400
        
        # Check for duplicate
        if FavoritesValidator.find_duplicate_favorite(current_favorites, filename=current_filename):
            return jsonify({"error": "This video is already in favorites"}), 400
        
        favorite = FavoritesValidator.create_favorite_from_offline(name, current_filename)
    
    if not favorite:
        return jsonify({"error": "Could not create favorite"}), 400
    
    # Add to favorites list
    current_favorites.append(favorite)
    
    # Save state
    if state_manager.update_field('user_favorites', current_favorites):
        logger.info(f"Added favorite: {favorite['name']} ({favorite['source']})")
        return jsonify({"success": True, "favorite": favorite})
    
    return jsonify({"error": "Failed to save favorite"}), 500

@app.route('/api/favorites/remove', methods=['DELETE'])
def remove_favorite():
    """Remove a favorite by ID"""
    data = request.get_json()
    if not data or 'id' not in data:
        return jsonify({"error": "Favorite ID required"}), 400
    
    favorite_id = data['id']
    if not FavoritesValidator.validate_favorite_id(favorite_id):
        return jsonify({"error": "Invalid favorite ID"}), 400
    
    state = state_manager.load_state()
    current_favorites = state.get('user_favorites', [])
    
    # Find and remove the favorite
    updated_favorites = [fav for fav in current_favorites if fav.get('id') != favorite_id]
    
    if len(updated_favorites) == len(current_favorites):
        return jsonify({"error": "Favorite not found"}), 404
    
    # Save updated state
    if state_manager.update_field('user_favorites', updated_favorites):
        logger.info(f"Removed favorite with ID: {favorite_id}")
        return jsonify({"success": True, "removed_id": favorite_id})
    
    return jsonify({"error": "Failed to remove favorite"}), 500

@app.route('/api/favorites/select', methods=['POST'])
def select_favorite():
    """Select a favorite and switch to it"""
    data = request.get_json()
    if not data or 'id' not in data:
        return jsonify({"error": "Favorite ID required"}), 400
    
    favorite_id = data['id']
    if not FavoritesValidator.validate_favorite_id(favorite_id):
        return jsonify({"error": "Invalid favorite ID"}), 400
    
    state = state_manager.load_state()
    current_favorites = state.get('user_favorites', [])
    
    # Find the favorite
    favorite = None
    for fav in current_favorites:
        if fav.get('id') == favorite_id:
            favorite = fav
            break
    
    if not favorite:
        return jsonify({"error": "Favorite not found"}), 404
    
    # Switch to the favorite content
    success = False
    if favorite['source'] == 'online':
        url = favorite.get('url')
        if url and URLValidator.is_valid_youtube_url(url):
            success = state_manager.update_field('last_online_url', url)
            if success and state.get('mode') != 'online':
                success = state_manager.update_field('mode', 'online')
    
    elif favorite['source'] == 'offline':
        filename = favorite.get('filename')
        if filename:
            # Verify file still exists
            videos = get_available_videos()
            if any(v['filename'] == filename for v in videos):
                success = state_manager.update_field('selected_offline', filename)
                if success and state.get('mode') != 'offline':
                    success = state_manager.update_field('mode', 'offline')
            else:
                return jsonify({"error": "Video file no longer exists"}), 404
    
    if success:
        logger.info(f"Selected favorite: {favorite['name']}")
        return jsonify({
            "success": True, 
            "favorite": favorite,
            "mode": favorite['source']  # online or offline
        })
    
    return jsonify({"error": "Failed to select favorite"}), 500

@app.route('/offline')
def offline_player():
    return send_from_directory(Path(__file__).parent / 'offline_player', 'offline.html')

@app.route('/static/offline/<path:filename>')
def offline_static(filename):
    return send_from_directory(Path(__file__).parent / 'offline_player', filename)

@app.route('/videos/<path:filename>')
def serve_video(filename):
    """Serve video files from the videos directory"""
    # Sanitize filename to prevent directory traversal
    if not FileValidator.is_supported_video(filename):
        return "Invalid video format", 400
    
    # Try production path first, then development path
    videos_dir = Path(VIDEOS_DIR)
    if not videos_dir.exists():
        videos_dir = Path('/opt/fireplace/videos')
    
    if not videos_dir.exists():
        logger.error(f"Videos directory not found: {videos_dir}")
        return "Videos directory not found", 500
    
    video_path = videos_dir / filename
    
    # Security check - ensure file is within videos directory
    try:
        video_path = video_path.resolve()
        videos_dir = videos_dir.resolve()
        if not str(video_path).startswith(str(videos_dir)):
            return "Access denied", 403
    except Exception:
        return "Invalid path", 400
    
    if not video_path.is_file():
        logger.warning(f"Video file not found: {filename}")
        return "Video not found", 404
    
    # Serve with appropriate MIME type
    mime_type = 'video/mp4'
    if filename.lower().endswith('.webm'):
        mime_type = 'video/webm'
    elif filename.lower().endswith('.mkv'):
        mime_type = 'video/x-matroska'
    elif filename.lower().endswith('.avi'):
        mime_type = 'video/x-msvideo'
    elif filename.lower().endswith('.mov'):
        mime_type = 'video/quicktime'
    
    return send_from_directory(str(videos_dir), filename, mimetype=mime_type)

@app.route('/api/kiosk/stop', methods=['POST'])
def stop_kiosk():
    """Stop the kiosk service"""
    try:
        import subprocess
        # Stop the kiosk service
        result = subprocess.run(
            ['/usr/bin/sudo', '/usr/bin/systemctl', 'stop', 'fire-kiosk.service'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0:
            logger.info("Kiosk service stopped successfully")
            return jsonify({"success": True, "message": "Kiosk stopped"})
        else:
            logger.error(f"Failed to stop kiosk: {result.stderr}")
            return jsonify({"success": False, "error": result.stderr}), 500
            
    except subprocess.TimeoutExpired:
        return jsonify({"success": False, "error": "Command timed out"}), 500
    except Exception as e:
        logger.error(f"Error stopping kiosk: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route('/api/kiosk/start', methods=['POST'])
def start_kiosk():
    """Start the kiosk service"""
    try:
        import subprocess
        # Start the kiosk service
        result = subprocess.run(
            ['/usr/bin/sudo', '/usr/bin/systemctl', 'start', 'fire-kiosk.service'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0:
            logger.info("Kiosk service started successfully")
            return jsonify({"success": True, "message": "Kiosk started"})
        else:
            logger.error(f"Failed to start kiosk: {result.stderr}")
            return jsonify({"success": False, "error": result.stderr}), 500
            
    except subprocess.TimeoutExpired:
        return jsonify({"success": False, "error": "Command timed out"}), 500
    except Exception as e:
        logger.error(f"Error starting kiosk: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route('/api/kiosk/status', methods=['GET'])
def kiosk_status():
    """Get the status of the kiosk service"""
    try:
        import subprocess
        result = subprocess.run(
            ['/usr/bin/systemctl', 'is-active', 'fire-kiosk.service'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        is_active = result.stdout.strip() == 'active'
        return jsonify({
            "success": True,
            "active": is_active,
            "status": result.stdout.strip()
        })
        
    except Exception as e:
        logger.error(f"Error checking kiosk status: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route('/api/system/shutdown', methods=['POST'])
def shutdown_system():
    """Safely shutdown the Raspberry Pi"""
    try:
        import subprocess
        logger.warning("System shutdown requested via web interface")
        
        # Use sudo shutdown immediately (with short delay to send response)
        result = subprocess.run(
            ['/usr/bin/sudo', '/usr/sbin/shutdown', '-h', 'now', 'Shutdown requested from fireplace control'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0:
            logger.info("System shutdown initiated successfully")
            return jsonify({
                "success": True, 
                "message": "System is shutting down now"
            })
        else:
            logger.error(f"Failed to initiate shutdown: {result.stderr}")
            return jsonify({"success": False, "error": result.stderr}), 500
            
    except subprocess.TimeoutExpired:
        return jsonify({"success": False, "error": "Shutdown command timed out"}), 500
    except Exception as e:
        logger.error(f"Error initiating shutdown: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route('/api/system/reboot', methods=['POST'])
def reboot_system():
    """Safely reboot the Raspberry Pi"""
    try:
        import subprocess
        logger.warning("System reboot requested via web interface")
        
        # Use sudo reboot immediately (with short delay to send response)
        result = subprocess.run(
            ['/usr/bin/sudo', '/usr/sbin/shutdown', '-r', 'now', 'Reboot requested from fireplace control'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0:
            logger.info("System reboot initiated successfully")
            return jsonify({
                "success": True, 
                "message": "System is rebooting now"
            })
        else:
            logger.error(f"Failed to initiate reboot: {result.stderr}")
            return jsonify({"success": False, "error": result.stderr}), 500
            
    except subprocess.TimeoutExpired:
        return jsonify({"success": False, "error": "Reboot command timed out"}), 500
    except Exception as e:
        logger.error(f"Error initiating reboot: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route('/api/scheduled-shutdown', methods=['GET'])
def get_scheduled_shutdown():
    """Get scheduled shutdown configuration"""
    state = state_manager.load_state()
    schedule = state.get('scheduled_shutdown', {
        'enabled': False,
        'time': '02:00',
        'weekdays_only': False
    })
    return jsonify({"success": True, "schedule": schedule})

@app.route('/api/scheduled-shutdown', methods=['POST'])
def set_scheduled_shutdown():
    """Update scheduled shutdown configuration"""
    data = request.get_json()
    if not data:
        return jsonify({"error": "Configuration data required"}), 400
    
    # Validate the configuration
    schedule = {}
    
    # Validate enabled flag
    if 'enabled' in data:
        if not isinstance(data['enabled'], bool):
            return jsonify({"error": "Enabled must be true or false"}), 400
        schedule['enabled'] = data['enabled']
    
    # Validate time format
    if 'time' in data:
        time_str = data['time']
        if not isinstance(time_str, str):
            return jsonify({"error": "Time must be a string"}), 400
        
        # Validate HH:MM format
        try:
            from datetime import datetime
            datetime.strptime(time_str, '%H:%M')
            schedule['time'] = time_str
        except ValueError:
            return jsonify({"error": "Time must be in HH:MM format (24-hour)"}), 400
    
    # Validate weekdays_only flag
    if 'weekdays_only' in data:
        if not isinstance(data['weekdays_only'], bool):
            return jsonify({"error": "Weekdays_only must be true or false"}), 400
        schedule['weekdays_only'] = data['weekdays_only']
    
    # Get current configuration and update with new values
    state = state_manager.load_state()
    current_schedule = state.get('scheduled_shutdown', {})
    current_schedule.update(schedule)
    
    # Save updated configuration
    if state_manager.update_field('scheduled_shutdown', current_schedule):
        logger.info(f"Scheduled shutdown updated: {current_schedule}")
        
        # Update systemd timer if time changed
        if 'time' in schedule:
            update_systemd_timer(schedule['time'])
        
        return jsonify({"success": True, "schedule": current_schedule})
    
    return jsonify({"error": "Failed to save scheduled shutdown configuration"}), 500

def update_systemd_timer(time_str):
    """Update the systemd timer with new schedule time"""
    try:
        import subprocess
        
        # Create new timer content
        timer_content = f"""[Unit]
Description=Fireplace Scheduled Shutdown Timer
Requires=fireplace-scheduled-shutdown.service

[Timer]
OnCalendar=*-*-* {time_str}:00
Persistent=true

[Install]
WantedBy=timers.target
"""
        
        # Write to timer file (requires appropriate permissions)
        timer_file = "/etc/systemd/system/fireplace-scheduled-shutdown.timer"
        
        # Use sudo to write the file
        result = subprocess.run(
            ['/usr/bin/sudo', 'tee', timer_file],
            input=timer_content,
            text=True,
            capture_output=True,
            timeout=5
        )
        
        if result.returncode == 0:
            # Reload systemd and restart timer
            subprocess.run(['/usr/bin/sudo', 'systemctl', 'daemon-reload'], timeout=5)
            subprocess.run(['/usr/bin/sudo', 'systemctl', 'restart', 'fireplace-scheduled-shutdown.timer'], timeout=5)
            logger.info(f"Updated systemd timer for {time_str}")
        else:
            logger.error(f"Failed to update systemd timer: {result.stderr}")
            
    except Exception as e:
        logger.error(f"Error updating systemd timer: {e}")


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)