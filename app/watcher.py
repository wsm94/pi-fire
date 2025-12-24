#!/usr/bin/env python3

import json
import os
import time
import subprocess
import signal
import sys
import logging
from pathlib import Path
from typing import Dict, Any, Optional
import requests
import psutil

try:
    # Try relative import first (when run as module)
    from .validators import ConfigValidator, URLValidator
except ImportError:
    # Fall back to direct import (when run as script)
    from validators import ConfigValidator, URLValidator

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class NetworkMonitor:
    def __init__(self, config: Dict[str, Any]):
        self.config = config.get('network', {})
        self.check_interval = self.config.get('check_interval', 5)
        self.check_timeout = self.config.get('check_timeout', 2)
        self.endpoints = self.config.get('check_endpoints', ['https://8.8.8.8/'])
        self.is_online = None
        self._last_check = 0
    
    def check_connectivity(self) -> bool:
        if time.time() - self._last_check < self.check_interval:
            return self.is_online
        
        for endpoint in self.endpoints:
            try:
                response = requests.get(
                    endpoint,
                    timeout=self.check_timeout,
                    headers={'User-Agent': 'FireplaceNetworkCheck/1.0'}
                )
                if response.status_code == 200:
                    if self.is_online is False:
                        logger.info("Network connectivity restored")
                    self.is_online = True
                    self._last_check = time.time()
                    return True
            except (requests.RequestException, Exception) as e:
                logger.debug(f"Endpoint {endpoint} failed: {e}")
                continue
        
        if self.is_online is True:
            logger.warning("Network connectivity lost")
        self.is_online = False
        self._last_check = time.time()
        return False

class ChromiumManager:
    def __init__(self):
        self.process = None
        self.current_target = None
        self.profile_dir = "/opt/fireplace/chromium-profile"
        self.user_data_dir = Path(self.profile_dir)
        self.is_youtube_url = False

    def get_chromium_flags(self) -> list:
        flags = [
            'chromium-browser',
            '--kiosk',
            '--noerrdialogs',
            '--disable-session-crashed-bubble',
            '--disable-infobars',
            '--autoplay-policy=no-user-gesture-required',
            '--start-fullscreen',
            '--overscroll-history-navigation=0',
            '--disable-features=TranslateUI',
            '--disable-background-timer-throttling',
            f'--user-data-dir={self.user_data_dir}',
            '--no-sandbox',
            '--disable-dev-shm-usage',
            '--disable-web-security',
            '--disable-default-apps'
        ]

        return flags
    
    def launch(self, target_url: str) -> bool:
        if self.is_running() and self.current_target == target_url:
            logger.debug(f"Chromium already running with target: {target_url}")
            return True
        
        self.stop()
        
        flags = self.get_chromium_flags()
        flags.append(target_url)
        
        try:
            logger.info(f"Launching Chromium with target: {target_url}")

            # Add environment variables for display access
            env = os.environ.copy()
            env['DISPLAY'] = ':0'
            # Try to detect the correct user's home directory
            # This will work for both 'pi' and 'will' users
            import pwd
            try:
                user_home = pwd.getpwuid(os.getuid()).pw_dir
                env['XAUTHORITY'] = f'{user_home}/.Xauthority'
            except:
                # Fallback to common locations
                if os.path.exists('/home/will/.Xauthority'):
                    env['XAUTHORITY'] = '/home/will/.Xauthority'
                elif os.path.exists('/home/pi/.Xauthority'):
                    env['XAUTHORITY'] = '/home/pi/.Xauthority'
                else:
                    env['XAUTHORITY'] = os.path.expanduser('~/.Xauthority')

            logger.debug(f"Using XAUTHORITY: {env.get('XAUTHORITY')}")

            self.process = subprocess.Popen(
                flags,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                preexec_fn=os.setsid if hasattr(os, 'setsid') else None
            )
            self.current_target = target_url
            self.is_youtube_url = 'youtube.com' in target_url
            time.sleep(2)  # Give Chromium time to start

            if self.is_running():
                logger.info(f"Chromium started successfully (PID: {self.process.pid})")

                # If YouTube, automate play and fullscreen using xdotool
                if self.is_youtube_url:
                    self._automate_youtube_playback(env)

                return True
            else:
                # Try to capture any error output
                try:
                    stdout, stderr = self.process.communicate(timeout=0.5)
                    if stderr:
                        logger.error(f"Chromium failed to start. Stderr: {stderr.decode()[:500]}")
                    if stdout:
                        logger.debug(f"Chromium stdout: {stdout.decode()[:500]}")
                except:
                    pass
                logger.error("Chromium failed to start")
                return False
                
        except Exception as e:
            logger.error(f"Failed to launch Chromium: {e}")
            return False
    
    def is_running(self) -> bool:
        if self.process is None:
            return False
        
        try:
            return self.process.poll() is None
        except:
            return False
    
    def stop(self):
        if self.process:
            try:
                logger.info("Stopping Chromium...")
                if hasattr(os, 'killpg'):
                    os.killpg(os.getpgid(self.process.pid), signal.SIGTERM)
                else:
                    self.process.terminate()
                
                # Wait for graceful shutdown
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    logger.warning("Chromium didn't stop gracefully, forcing kill")
                    if hasattr(os, 'killpg'):
                        os.killpg(os.getpgid(self.process.pid), signal.SIGKILL)
                    else:
                        self.process.kill()
                
                self.process = None
                self.current_target = None
                logger.info("Chromium stopped")
                
            except Exception as e:
                logger.error(f"Error stopping Chromium: {e}")
    
    def restart(self):
        target = self.current_target
        self.stop()
        if target:
            time.sleep(1)
            return self.launch(target)
        return False

    def _automate_youtube_playback(self, env: dict):
        """Use xdotool to automate YouTube play and fullscreen."""
        try:
            # Wait for YouTube page to fully load
            logger.info("Waiting for YouTube to load before automation...")
            time.sleep(5)

            # Click in the center of the screen to focus the video player
            # Then press 'k' to play and 'f' for fullscreen
            xdotool_env = env.copy()

            # First, click to dismiss any popups and focus the player
            subprocess.run(
                ['xdotool', 'mousemove', '--screen', '0', '960', '540', 'click', '1'],
                env=xdotool_env,
                timeout=5
            )
            time.sleep(0.5)

            # Press 'k' to play/pause (starts playback)
            subprocess.run(
                ['xdotool', 'key', 'k'],
                env=xdotool_env,
                timeout=5
            )
            time.sleep(0.5)

            # Press 't' to exit theatre mode
            subprocess.run(
                ['xdotool', 'key', 't'],
                env=xdotool_env,
                timeout=5
            )
            time.sleep(5)

            # Press 'f' to enter fullscreen
            subprocess.run(
                ['xdotool', 'key', 'f'],
                env=xdotool_env,
                timeout=5
            )
            time.sleep(0.5)

            # Move mouse to corner to hide it
            subprocess.run(
                ['xdotool', 'mousemove', '--screen', '0', '0', '0'],
                env=xdotool_env,
                timeout=5
            )

            logger.info("YouTube automation completed (play + fullscreen)")

        except subprocess.TimeoutExpired:
            logger.warning("xdotool command timed out")
        except FileNotFoundError:
            logger.error("xdotool not installed - run: sudo apt install xdotool")
        except Exception as e:
            logger.error(f"YouTube automation failed: {e}")

class FireplaceWatcher:
    def __init__(self):
        self.state_file = "/opt/fireplace/state.json"
        self.policy_file = "/opt/fireplace/config/policy.json"
        self.offline_url = "http://localhost:8080/offline"
        self.youtube_url = "http://localhost:8080/youtube"
        
        # Development paths
        if not Path(self.state_file).exists():
            self.state_file = Path(__file__).parent.parent / "config" / "state_default.json"
        if not Path(self.policy_file).exists():
            self.policy_file = Path(__file__).parent.parent / "config" / "policy.json"
        
        self.validator = ConfigValidator()
        self.load_config()
        
        self.network_monitor = NetworkMonitor(self.config)
        self.chromium_manager = ChromiumManager()
        
        self.current_state = {}
        self.running = False
        
    def load_config(self):
        try:
            with open(self.policy_file, 'r') as f:
                self.config = json.load(f)
            logger.info("Configuration loaded")
        except Exception as e:
            logger.error(f"Failed to load configuration: {e}")
            self.config = {"network": {"check_interval": 5, "check_timeout": 2, "check_endpoints": ["https://8.8.8.8/"]}}
    
    def load_state(self) -> Dict[str, Any]:
        try:
            with open(self.state_file, 'r') as f:
                state = json.load(f)
                if self.validator.validate_state(state):
                    return state
                else:
                    logger.warning("State validation failed, using defaults")
                    return self._default_state()
        except Exception as e:
            logger.warning(f"Failed to load state: {e}")
            return self._default_state()
    
    def _default_state(self) -> Dict[str, Any]:
        return {
            "mode": "offline",
            "volume": 60,
            "muted": True,
            "version": "1.0"
        }
    
    def get_target_url(self, state: Dict[str, Any]) -> str:
        mode = state.get('mode', 'offline')

        if mode == 'online' and state.get('last_online_url'):
            # Load YouTube directly (not in iframe) to bypass embed restrictions
            youtube_url = URLValidator.build_youtube_fullpage_url(state['last_online_url'])
            if youtube_url:
                return youtube_url

        # Default to offline mode
        return self.offline_url
    
    def should_switch_to_offline(self, current_mode: str, is_online: bool) -> bool:
        if current_mode != 'online':
            return False
            
        if not is_online:
            return True
            
        return False
    
    def should_switch_to_online(self, current_mode: str, is_online: bool, state: Dict[str, Any]) -> bool:
        if current_mode != 'offline':
            return False
            
        if not is_online:
            return False
            
        # Check if we have a valid online URL and auto-restore is enabled
        if state.get('last_online_url') and not state.get('stick_offline_until_manual', False):
            return True
            
        return False
    
    def run_cycle(self):
        state = self.load_state()
        is_online = self.network_monitor.check_connectivity()
        
        # Determine target URL based on current conditions
        current_mode = state.get('mode', 'offline')
        target_url = None
        
        # Check if we should auto-switch modes
        if self.should_switch_to_offline(current_mode, is_online):
            logger.info("Switching to offline mode due to network loss")
            target_url = self.offline_url
            current_mode = 'offline'
        elif self.should_switch_to_online(current_mode, is_online, state):
            logger.info("Auto-restoring online mode")
            target_url = self.get_target_url(state)
            current_mode = 'online'
        else:
            target_url = self.get_target_url(state)
        
        # Check if Chromium is running with the correct target
        if not self.chromium_manager.is_running() or self.chromium_manager.current_target != target_url:
            logger.info(f"Starting/restarting Chromium with target: {target_url}")
            success = self.chromium_manager.launch(target_url)
            if not success:
                logger.error("Failed to launch Chromium, retrying in 10 seconds")
                time.sleep(10)
                return
        
        # Check if state changed significantly
        if state != self.current_state:
            logger.info("State changed, updating current state")
            self.current_state = state.copy()
    
    def run(self):
        self.running = True
        logger.info("Fireplace watcher started")
        
        # Initial launch
        state = self.load_state()
        target_url = self.get_target_url(state)
        self.chromium_manager.launch(target_url)
        
        try:
            while self.running:
                self.run_cycle()
                time.sleep(self.config.get('network', {}).get('check_interval', 5))
                
        except KeyboardInterrupt:
            logger.info("Shutting down watcher...")
        except Exception as e:
            logger.error(f"Watcher error: {e}")
        finally:
            self.cleanup()
    
    def cleanup(self):
        logger.info("Cleaning up...")
        self.chromium_manager.stop()
        self.running = False
    
    def signal_handler(self, signum, frame):
        logger.info(f"Received signal {signum}")
        self.running = False

def main():
    watcher = FireplaceWatcher()
    
    # Set up signal handlers
    signal.signal(signal.SIGTERM, watcher.signal_handler)
    signal.signal(signal.SIGINT, watcher.signal_handler)
    
    try:
        watcher.run()
    except Exception as e:
        logger.error(f"Watcher failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    import os
    main()