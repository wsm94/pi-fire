#!/usr/bin/env python3

"""
Scheduled shutdown script for Fireplace Pi
Checks if scheduled shutdown is enabled and executes shutdown if conditions are met
"""

import json
import logging
import subprocess
import sys
from datetime import datetime, time
from pathlib import Path

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/fireplace/scheduled_shutdown.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

STATE_FILE = "/opt/fireplace/state.json"
STATE_FILE_DEV = Path(__file__).parent.parent / "config" / "state_default.json"

def load_state():
    """Load the current state configuration"""
    state_file = STATE_FILE if Path(STATE_FILE).exists() else STATE_FILE_DEV
    
    try:
        with open(state_file, 'r') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Failed to load state file: {e}")
        return None

def should_shutdown(schedule_config):
    """Check if we should shutdown based on schedule configuration"""
    if not schedule_config.get('enabled', False):
        logger.info("Scheduled shutdown is disabled")
        return False
    
    # Parse the scheduled time
    try:
        schedule_time_str = schedule_config.get('time', '02:00')
        schedule_time = datetime.strptime(schedule_time_str, '%H:%M').time()
    except ValueError as e:
        logger.error(f"Invalid schedule time format: {e}")
        return False
    
    # Get current time
    current_time = datetime.now().time()
    current_weekday = datetime.now().weekday()  # 0 = Monday, 6 = Sunday
    
    # Check if we should only shutdown on weekdays
    weekdays_only = schedule_config.get('weekdays_only', False)
    if weekdays_only and current_weekday >= 5:  # 5 = Saturday, 6 = Sunday
        logger.info("Weekdays-only mode enabled, skipping weekend shutdown")
        return False
    
    # Check if current time matches schedule (within a 1-minute window)
    # This accounts for the timer not running at exactly the scheduled time
    current_minutes = current_time.hour * 60 + current_time.minute
    schedule_minutes = schedule_time.hour * 60 + schedule_time.minute
    
    # Allow 1-minute window before and after scheduled time
    if abs(current_minutes - schedule_minutes) <= 1:
        logger.info(f"Time matches schedule: {current_time} ≈ {schedule_time}")
        return True
    
    logger.info(f"Time does not match schedule: {current_time} != {schedule_time}")
    return False

def execute_shutdown():
    """Execute system shutdown"""
    try:
        logger.warning("Executing scheduled shutdown")
        
        # Use the same shutdown command as the web interface
        result = subprocess.run(
            ['/usr/bin/sudo', '/usr/sbin/shutdown', '-h', 'now', 'Scheduled shutdown from fireplace control'],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode == 0:
            logger.info("Shutdown command executed successfully")
            return True
        else:
            logger.error(f"Shutdown command failed: {result.stderr}")
            return False
            
    except subprocess.TimeoutExpired:
        logger.error("Shutdown command timed out")
        return False
    except Exception as e:
        logger.error(f"Error executing shutdown: {e}")
        return False

def main():
    """Main execution function"""
    logger.info("Scheduled shutdown check started")
    
    # Load state configuration
    state = load_state()
    if not state:
        logger.error("Failed to load state, aborting")
        sys.exit(1)
    
    # Get schedule configuration
    schedule_config = state.get('scheduled_shutdown', {})
    
    # Check if we should shutdown
    if should_shutdown(schedule_config):
        logger.info("Conditions met for scheduled shutdown")
        
        # Execute shutdown
        if execute_shutdown():
            logger.info("Scheduled shutdown initiated successfully")
            sys.exit(0)
        else:
            logger.error("Failed to initiate scheduled shutdown")
            sys.exit(1)
    else:
        logger.info("Scheduled shutdown conditions not met")
        sys.exit(0)

if __name__ == "__main__":
    main()