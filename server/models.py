from pydantic import BaseModel
from typing import Dict, List, Optional, Any

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
    event_type: str # 'listen', 'skip', 'complete'
    timestamp: float
    platform: Optional[str] = "unknown"
    foreground_duration: Optional[Any] = "unknown"
    background_duration: Optional[Any] = "unknown"

class ShuffleConfig(BaseModel):
    enabled: bool = False
    anti_repeat_enabled: bool = True
    streak_breaker_enabled: bool = True
    favorite_multiplier: float = 1.15
    suggest_less_multiplier: float = 0.2
    history_limit: int = 50

class ShuffleState(BaseModel):
    config: ShuffleConfig = ShuffleConfig()
    history: List[str] = []

class StatsSummary(BaseModel):
    total_play_time: float = 0.0
    total_sessions: int = 0
    shuffle_state: ShuffleState = ShuffleState()

class PlaylistSong(BaseModel):
    filename: str
    added_at: float

class Playlist(BaseModel):
    id: str
    name: str
    songs: List[PlaylistSong] = [] 

class PlaylistCreate(BaseModel):
    name: str

class PlaylistAddSong(BaseModel):
    song_filename: str

class FavoriteRequest(BaseModel):
    song_filename: str
    session_id: str
