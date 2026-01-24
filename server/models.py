from pydantic import BaseModel
from typing import Dict, List, Optional, Any

from enum import Enum

class UserBase(BaseModel):
    username: str

class UserCreate(UserBase):
    password: str

class UserLogin(UserBase):
    password: str

class UserUpdate(BaseModel):
    old_password: str
    new_password: str

class UserProfileUpdate(BaseModel):
    new_username: Optional[str] = None
    
class StatsEntry(BaseModel):
    session_id: str
    song_filename: str
    duration_played: float
    total_length: float = 0.0
    event_type: str # 'listen', 'skip', 'complete'
    timestamp: float
    platform: Optional[str] = "unknown"
    foreground_duration: Optional[Any] = "unknown"
    background_duration: Optional[Any] = "unknown"

class ShufflePersonality(str, Enum):
    DEFAULT = "default"
    EXPLORER = "explorer"
    CONSISTENT = "consistent"

class ShuffleConfig(BaseModel):
    enabled: bool = False
    anti_repeat_enabled: bool = True
    streak_breaker_enabled: bool = True
    favorite_multiplier: float = 1.15
    suggest_less_multiplier: float = 0.2
    history_limit: int = 50
    personality: ShufflePersonality = ShufflePersonality.DEFAULT

class ShuffleState(BaseModel):
    config: ShuffleConfig = ShuffleConfig()
    history: List[dict] = [] # List of {"filename": str, "timestamp": float}

class QueueItem(BaseModel):
    queue_id: str
    song_filename: str
    is_priority: bool = False
    added_at: float = 0.0

class QueueState(BaseModel):
    items: List[QueueItem] = []
    current_index: int = 0
    version: int = 0

class QueueSyncRequest(BaseModel):
    queue: List[QueueItem]
    current_index: int
    version: int

class StatsSummary(BaseModel):
    total_play_time: float = 0.0
    total_sessions: int = 0
    shuffle_state: ShuffleState = ShuffleState()
    queue_state: Optional[QueueState] = None

class FavoriteRequest(BaseModel):
    song_filename: str
    session_id: str = "unknown"

class RenameRequest(BaseModel):
    old_filename: str
    new_name: str # Can be new filename or new title
    type: str = "file" # "file" or "metadata"
    device_count: int = 0
    artist: Optional[str] = None
    album: Optional[str] = None

class AcknowledgeRenameRequest(BaseModel):
    old_filename: str
    new_name: str
    type: str = "file"
    artist: Optional[str] = None
    album: Optional[str] = None
