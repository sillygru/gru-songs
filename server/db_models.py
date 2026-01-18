from typing import List, Optional
from sqlmodel import Field, SQLModel, Relationship
from datetime import datetime

# --- global_users.db ---
class GlobalUser(SQLModel, table=True):
    username: str = Field(primary_key=True, index=True)
    created_at: float
    # We can store a summary snapshot here if needed, but the prompt said 
    # "lists all users AND has their global stats summary".
    # We'll store the summary as a JSON string to be flexible/robust
    stats_summary_json: str = Field(default="{}") 

# --- uploads.db ---
class Upload(SQLModel, table=True):
    filename: str = Field(primary_key=True)
    uploader_username: str = Field(index=True)
    title: str
    source: str
    original_filename: str
    youtube_url: Optional[str] = None
    timestamp: float

# --- [username]_data.db ---
class UserData(SQLModel, table=True):
    username: str = Field(primary_key=True)
    password_hash: str
    created_at: float

class Favorite(SQLModel, table=True):
    filename: str = Field(primary_key=True)
    added_at: float = Field(default_factory=lambda: datetime.now().timestamp())

class SuggestLess(SQLModel, table=True):
    filename: str = Field(primary_key=True)
    added_at: float = Field(default_factory=lambda: datetime.now().timestamp())

# --- [username]_stats.db ---
class PlaySession(SQLModel, table=True):
    id: str = Field(primary_key=True)
    start_time: float
    end_time: float
    platform: str = Field(default="unknown")
    events: List["PlayEvent"] = Relationship(back_populates="session", sa_relationship_kwargs={"cascade": "all, delete"})

class PlayEvent(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    session_id: str = Field(foreign_key="playsession.id")
    song_filename: str
    event_type: str
    
    # Switched to NULL (Optional[float]) for performance as requested
    timestamp: float
    duration_played: float 
    total_length: float
    play_ratio: float
    foreground_duration: Optional[float] = None
    background_duration: Optional[float] = None
    
    session: Optional[PlaySession] = Relationship(back_populates="events")

# Note: [username]_final_stats.json is not a DB model, it's just a JSON file.
