#!/usr/bin/env python3

import sys
import json
import os
from pathlib import Path

# Add app directory to Python path
sys.path.insert(0, str(Path(__file__).parent.parent / "app"))

def test_imports():
    """Test that all modules can be imported"""
    print("Testing imports...")
    
    try:
        import validators
        print("✅ validators module imported")
    except ImportError as e:
        print(f"❌ Failed to import validators: {e}")
        return False
    
    try:
        # Test server imports (without running Flask)
        import server
        print("✅ server module imported")
    except ImportError as e:
        print(f"❌ Failed to import server: {e}")
        return False
    
    try:
        import watcher
        print("✅ watcher module imported")
    except ImportError as e:
        print(f"❌ Failed to import watcher: {e}")
        return False
    
    return True

def test_validators():
    """Test validator functions"""
    print("\nTesting validators...")
    
    from validators import URLValidator, validate_volume, validate_mode
    
    # Test YouTube URL validation
    test_urls = [
        ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", True),
        ("https://youtu.be/dQw4w9WgXcQ", True), 
        ("https://youtube.com/shorts/abc123", True),
        ("https://example.com", False),
        ("not-a-url", False)
    ]
    
    for url, expected in test_urls:
        result = URLValidator.is_valid_youtube_url(url)
        status = "✅" if result == expected else "❌"
        print(f"{status} YouTube URL '{url}': {result} (expected {expected})")
    
    # Test volume validation
    test_volumes = [
        (50, 50),
        ("75", 75),
        (0, 0),
        (100, 100),
        (150, None),
        ("invalid", None)
    ]
    
    for input_vol, expected in test_volumes:
        result = validate_volume(input_vol)
        status = "✅" if result == expected else "❌"
        print(f"{status} Volume '{input_vol}': {result} (expected {expected})")
    
    # Test mode validation
    test_modes = [
        ("online", "online"),
        ("offline", "offline"),
        ("invalid", None),
        (None, None)
    ]
    
    for mode, expected in test_modes:
        result = validate_mode(mode)
        status = "✅" if result == expected else "❌"
        print(f"{status} Mode '{mode}': {result} (expected {expected})")

def test_config_files():
    """Test configuration file loading"""
    print("\nTesting configuration files...")
    
    config_dir = Path(__file__).parent.parent / "config"
    
    # Test state file
    state_file = config_dir / "state_default.json"
    try:
        with open(state_file) as f:
            state = json.load(f)
        print(f"✅ State file loaded: {len(state)} keys")
    except Exception as e:
        print(f"❌ Failed to load state file: {e}")
    
    # Test policy file
    policy_file = config_dir / "policy.json"
    try:
        with open(policy_file) as f:
            policy = json.load(f)
        print(f"✅ Policy file loaded: {len(policy)} sections")
    except Exception as e:
        print(f"❌ Failed to load policy file: {e}")
    
    # Test presets file
    presets_file = config_dir / "presets.json"
    try:
        with open(presets_file) as f:
            presets = json.load(f)
        print(f"✅ Presets file loaded: {len(presets['presets'])} presets")
    except Exception as e:
        print(f"❌ Failed to load presets file: {e}")

def test_schema_validation():
    """Test JSON schema validation"""
    print("\nTesting schema validation...")
    
    try:
        from validators import ConfigValidator
        validator = ConfigValidator(str(Path(__file__).parent.parent / "config" / "schema.json"))
        
        # Test valid state
        valid_state = {
            "mode": "online",
            "volume": 60,
            "muted": True,
            "version": "1.0"
        }
        
        result = validator.validate_state(valid_state)
        status = "✅" if result else "❌"
        print(f"{status} Valid state validation: {result}")
        
        # Test invalid state
        invalid_state = {
            "mode": "invalid_mode",  # Invalid enum value
            "volume": 150,  # Out of range
            "muted": "not_boolean",  # Wrong type
            "version": "1.0"
        }
        
        result = validator.validate_state(invalid_state)
        status = "✅" if not result else "❌"
        print(f"{status} Invalid state validation: {result} (should be False)")
        
    except Exception as e:
        print(f"❌ Schema validation test failed: {e}")

def main():
    print("🔥 Fireplace Pi - Basic Tests")
    print("=" * 40)
    
    success = True
    
    success &= test_imports()
    test_validators()
    test_config_files()
    test_schema_validation()
    
    print("\n" + "=" * 40)
    if success:
        print("✅ Basic tests completed successfully!")
        print("\nTo run the development server:")
        print("1. Install dependencies: pip3 install -r requirements.txt")
        print("2. Run server: python3 app/server.py")
        print("3. Open: http://localhost:8080")
    else:
        print("❌ Some tests failed - check output above")
        sys.exit(1)

if __name__ == "__main__":
    main()