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
    song_filename: str
    duration_played: float
    event_type: str # 'play', 'pause', 'skip', 'complete', 'seek'
    timestamp: float
