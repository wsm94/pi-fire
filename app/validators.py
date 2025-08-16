import json
import re
import uuid
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, Optional
import jsonschema
from jsonschema import validate, ValidationError

class ConfigValidator:
    def __init__(self, schema_path: str = "/opt/fireplace/config/schema.json"):
        self.schema_path = schema_path
        self._schema = None
        
    def load_schema(self) -> Dict[str, Any]:
        if self._schema is None:
            try:
                with open(self.schema_path, 'r') as f:
                    self._schema = json.load(f)
            except FileNotFoundError:
                schema_fallback = Path(__file__).parent.parent / "config" / "schema.json"
                with open(schema_fallback, 'r') as f:
                    self._schema = json.load(f)
        return self._schema
    
    def validate_state(self, state_data: Dict[str, Any]) -> bool:
        schema = self.load_schema()
        try:
            validate(instance=state_data, schema=schema["definitions"]["state"])
            return True
        except ValidationError as e:
            print(f"State validation error: {e.message}")
            return False
    
    def validate_policy(self, policy_data: Dict[str, Any]) -> bool:
        schema = self.load_schema()
        try:
            validate(instance=policy_data, schema=schema["definitions"]["policy"])
            return True
        except ValidationError as e:
            print(f"Policy validation error: {e.message}")
            return False

class URLValidator:
    @staticmethod
    def extract_youtube_id(url: str) -> Optional[str]:
        youtube_patterns = [
            r'(?:youtube\.com/watch\?v=|youtu\.be/|youtube\.com/embed/)([^&\n?#]+)',
            r'youtube\.com/shorts/([^&\n?#]+)',
        ]
        
        for pattern in youtube_patterns:
            match = re.search(pattern, url)
            if match:
                return match.group(1)
        return None
    
    @staticmethod
    def is_valid_youtube_url(url: str) -> bool:
        return URLValidator.extract_youtube_id(url) is not None
    
    @staticmethod
    def build_youtube_embed(url: str, frontend_base: Optional[str] = None) -> Optional[str]:
        video_id = URLValidator.extract_youtube_id(url)
        if not video_id:
            return None
        
        if frontend_base:
            return f"{frontend_base.rstrip('/')}/embed/{video_id}?autoplay=1&controls=0&loop=1"
        else:
            params = "autoplay=1&controls=0&rel=0&mute=1&loop=1&modestbranding=1"
            return f"https://www.youtube.com/embed/{video_id}?{params}&playlist={video_id}"

class FileValidator:
    SUPPORTED_FORMATS = ['.mp4', '.webm', '.mkv', '.avi', '.mov']
    
    @staticmethod
    def is_supported_video(filename: str) -> bool:
        return any(filename.lower().endswith(fmt) for fmt in FileValidator.SUPPORTED_FORMATS)
    
    @staticmethod
    def sanitize_filename(filename: str) -> str:
        safe_chars = re.sub(r'[^a-zA-Z0-9._-]', '_', filename)
        return safe_chars[:255]
    
    @staticmethod
    def is_safe_path(path: str, base_dir: str) -> bool:
        try:
            resolved_path = Path(path).resolve()
            base_path = Path(base_dir).resolve()
            return resolved_path.is_relative_to(base_path)
        except (ValueError, OSError):
            return False

def validate_volume(volume: Any) -> Optional[int]:
    try:
        vol = int(volume)
        if 0 <= vol <= 100:
            return vol
    except (ValueError, TypeError):
        pass
    return None

def validate_mode(mode: Any) -> Optional[str]:
    if mode in ["online", "offline"]:
        return mode
    return None

class FavoritesValidator:
    @staticmethod
    def validate_favorite_name(name: str) -> Optional[str]:
        """Validate and sanitize favorite name"""
        if not isinstance(name, str):
            return None
        
        # Strip whitespace and limit length
        cleaned = name.strip()
        if not cleaned or len(cleaned) > 50:
            return None
        
        # Remove potentially dangerous characters
        safe_name = re.sub(r'[<>&"\'`]', '', cleaned)
        return safe_name if safe_name else None
    
    @staticmethod
    def create_favorite_from_online(name: str, url: str) -> Optional[Dict[str, Any]]:
        """Create a favorite from online YouTube URL"""
        validated_name = FavoritesValidator.validate_favorite_name(name)
        if not validated_name:
            return None
        
        if not URLValidator.is_valid_youtube_url(url):
            return None
        
        return {
            "id": f"fav_{uuid.uuid4().hex[:8]}",
            "name": validated_name,
            "url": url,
            "type": "favorite",
            "created_date": datetime.utcnow().isoformat() + "Z",
            "source": "online"
        }
    
    @staticmethod
    def create_favorite_from_offline(name: str, filename: str) -> Optional[Dict[str, Any]]:
        """Create a favorite from offline video file"""
        validated_name = FavoritesValidator.validate_favorite_name(name)
        if not validated_name:
            return None
        
        if not FileValidator.is_supported_video(filename):
            return None
        
        return {
            "id": f"fav_{uuid.uuid4().hex[:8]}",
            "name": validated_name,
            "filename": filename,
            "type": "favorite",
            "created_date": datetime.utcnow().isoformat() + "Z",
            "source": "offline"
        }
    
    @staticmethod
    def validate_favorite_id(favorite_id: str) -> bool:
        """Validate favorite ID format"""
        if not isinstance(favorite_id, str):
            return False
        return bool(re.match(r'^fav_[a-f0-9]{8}$', favorite_id))
    
    @staticmethod
    def find_duplicate_favorite(favorites: list, url: str = None, filename: str = None) -> Optional[Dict[str, Any]]:
        """Find if a duplicate favorite already exists"""
        for fav in favorites:
            if url and fav.get("source") == "online" and fav.get("url") == url:
                return fav
            elif filename and fav.get("source") == "offline" and fav.get("filename") == filename:
                return fav
        return None