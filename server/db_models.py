from typing import List, Optional
from sqlalchemy import Column, Integer, Float, String, ForeignKey, JSON
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from datetime import datetime

class Base(DeclarativeBase):
    pass

# --- global_users.db ---
class GlobalUser(Base):
    __tablename__ = "globaluser"
    username: Mapped[str] = mapped_column(String, primary_key=True, index=True)
    created_at: Mapped[float] = mapped_column(Float)
    # We store the summary snapshot here if needed.
    # We'll store the summary as a JSON string to be flexible/robust
    stats_summary_json: Mapped[str] = mapped_column(String, default="{}") 

# --- uploads.db ---
class Upload(Base):
    __tablename__ = "upload"
    filename: Mapped[str] = mapped_column(String, primary_key=True)
    uploader_username: Mapped[str] = mapped_column(String, index=True)
    title: Mapped[str] = mapped_column(String)
    source: Mapped[str] = mapped_column(String)
    original_filename: Mapped[str] = mapped_column(String)
    youtube_url: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    timestamp: Mapped[float] = mapped_column(Float)

# --- [username]_data.db ---
class UserData(Base):
    __tablename__ = "userdata"
    username: Mapped[str] = mapped_column(String, primary_key=True)
    password_hash: Mapped[str] = mapped_column(String)
    created_at: Mapped[float] = mapped_column(Float)

class Favorite(Base):
    __tablename__ = "favorite"
    filename: Mapped[str] = mapped_column(String, primary_key=True)
    added_at: Mapped[float] = mapped_column(Float, default=lambda: datetime.now().timestamp())

class SuggestLess(Base):
    __tablename__ = "suggestless"
    filename: Mapped[str] = mapped_column(String, primary_key=True)
    added_at: Mapped[float] = mapped_column(Float, default=lambda: datetime.now().timestamp())

# --- [username]_stats.db ---
class PlaySession(Base):
    __tablename__ = "playsession"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    start_time: Mapped[float] = mapped_column(Float)
    end_time: Mapped[float] = mapped_column(Float)
    platform: Mapped[str] = mapped_column(String, default="unknown")
    
    events: Mapped[List["PlayEvent"]] = relationship(
        "PlayEvent", back_populates="session", cascade="all, delete"
    )

class PlayEvent(Base):
    __tablename__ = "playevent"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    session_id: Mapped[str] = mapped_column(String, ForeignKey("playsession.id"))
    song_filename: Mapped[str] = mapped_column(String)
    event_type: Mapped[str] = mapped_column(String)
    
    timestamp: Mapped[float] = mapped_column(Float)
    duration_played: Mapped[float] = mapped_column(Float)
    total_length: Mapped[float] = mapped_column(Float)
    play_ratio: Mapped[float] = mapped_column(Float)
    foreground_duration: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    background_duration: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    
    session: Mapped[Optional["PlaySession"]] = relationship("PlaySession", back_populates="events")