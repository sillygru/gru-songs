import json
import os
import uuid
import time
import math
from typing import Dict, List
from passlib.context import CryptContext
from settings import settings
from models import StatsEntry, Playlist
from services import music_service

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

class UserService:
    def __init__(self):
        if not os.path.exists(settings.USERS_DIR):
            os.makedirs(settings.USERS_DIR)
        
        # Buffer: {username: [stats_dicts]}
        self._stats_buffer: Dict[str, List[dict]] = {}

    def _get_user_path(self, username: str) -> str:
        return os.path.join(settings.USERS_DIR, f"{username}.json")

    def _get_user_stats_path(self, username: str) -> str:
        return os.path.join(settings.USERS_DIR, f"{username}_stats.json")

    def _get_user_playlists_path(self, username: str) -> str:
        return os.path.join(settings.USERS_DIR, f"{username}_playlists.json")

    def get_user(self, username: str):
        path = self._get_user_path(username)
        if not os.path.exists(path):
            return None
        with open(path, "r") as f:
            return json.load(f)
            
    def _save_user(self, username: str, data: dict):
        # We no longer store playlists in the user profile, but we keep the key for compatibility if needed
        # We will migrate them to separate file on load/save if found
        if "playlists" in data:
            # If we are saving a user that still has playlists in its dict, 
            # and we haven't migrated yet, it's safer to just let it be or migrate now.
            # But the primary storage is now _playlists.json
            pass
        with open(self._get_user_path(username), "w") as f:
            json.dump(data, f, indent=4)

    def create_user(self, username: str, password: str):
        if self.get_user(username):
            return False, "User already exists"
        
        hashed_password = pwd_context.hash(password)
        user_data = {
            "username": username,
            "password": hashed_password,
            "created_at": str(os.path.getctime(settings.USERS_DIR)),
            "favorites": [],
            "suggest_less": []
        }
        
        self._save_user(username, user_data)
            
        with open(self._get_user_stats_path(username), "w") as f:
            json.dump({"sessions": [], "total_play_time": 0}, f, indent=4)

        with open(self._get_user_playlists_path(username), "w") as f:
            json.dump([], f, indent=4)
            
        return True, "User created"

    def authenticate_user(self, username: str, password: str):
        user = self.get_user(username)
        if not user:
            return False
        if not pwd_context.verify(password, user["password"]):
            return False
        return True

    def update_password(self, username: str, old_password: str, new_password: str):
        user = self.get_user(username)
        if not user:
            return False, "User not found"
        
        if not pwd_context.verify(old_password, user["password"]):
            return False, "Invalid old password"
        
        user["password"] = pwd_context.hash(new_password)
        self._save_user(username, user)
            
        return True, "Password updated"

    def update_username(self, current_username: str, new_username: str):
        if self.get_user(new_username):
            return False, "Username already taken"
        
        user = self.get_user(current_username)
        if not user:
            return False, "User not found"
        
        self.flush_stats()
        
        old_path = self._get_user_path(current_username)
        new_path = self._get_user_path(new_username)
        old_stats = self._get_user_stats_path(current_username)
        new_stats = self._get_user_stats_path(new_username)
        old_playlists = self._get_user_playlists_path(current_username)
        new_playlists = self._get_user_playlists_path(new_username)
        
        user["username"] = new_username
        
        with open(new_path, "w") as f:
            json.dump(user, f, indent=4)
            
        if os.path.exists(old_stats):
            os.rename(old_stats, new_stats)
        else:
             with open(new_stats, "w") as f:
                json.dump({"sessions": [], "total_play_time": 0}, f, indent=4)

        if os.path.exists(old_playlists):
            os.rename(old_playlists, new_playlists)

        os.remove(old_path)
        
        return True, "Username updated"

    # --- Statistics ---

    def append_stats(self, username: str, stats: StatsEntry):
        # Skip events with 0 duration unless it's a special marker (like favorite, but favorite is separate)
        if stats.duration_played <= 0 and stats.event_type != 'favorite':
            return

        total_length = music_service.get_song_duration(stats.song_filename)
        ratio = 0.0
        if total_length > 0:
            ratio = stats.duration_played / total_length
            
        entry_data = stats.dict()
        entry_data['duration_played'] = round(stats.duration_played, 2)
        entry_data['timestamp'] = round(stats.timestamp, 2)
        entry_data['total_length'] = round(total_length, 2)
        entry_data['play_ratio'] = round(ratio, 2)
        
        if username not in self._stats_buffer:
            self._stats_buffer[username] = []
            
        self._stats_buffer[username].append(entry_data)
        
    def flush_stats(self):
        if not self._stats_buffer:
            return

        for username, events in self._stats_buffer.items():
            if not events:
                continue
                
            path = self._get_user_stats_path(username)
            data = {"sessions": [], "total_play_time": 0}
            
            if os.path.exists(path):
                with open(path, "r") as f:
                    try:
                        data = json.load(f)
                    except:
                        pass 

            if "sessions" not in data:
                data["sessions"] = []
                
            # Process events into sessions
            for event in events:
                session_id = event.get('session_id')
                if not session_id:
                    continue # Should not happen
                
                # Find or create session
                session = next((s for s in data["sessions"] if s["id"] == session_id), None)
                if not session:
                    session = {
                        "id": session_id,
                        "start_time": event['timestamp'],
                        "end_time": event['timestamp'],
                        "events": []
                    }
                    data["sessions"].append(session)
                
                # Update session bounds
                if event['timestamp'] < session['start_time']:
                    session['start_time'] = event['timestamp']
                if event['timestamp'] > session['end_time']:
                    session['end_time'] = event['timestamp']
                    
                session["events"].append(event)
                
                # Update total play time
                if event.get('event_type') != 'favorite':
                    data["total_play_time"] = round(data["total_play_time"] + event.get("duration_played", 0), 2)

            # Ensure all numeric fields in the saved data are rounded
            if "sessions" in data:
                for s in data["sessions"]:
                    s["start_time"] = round(s["start_time"], 2)
                    s["end_time"] = round(s["end_time"], 2)
                    for e in s["events"]:
                        if 'duration_played' in e: e['duration_played'] = round(e['duration_played'], 2)
                        if 'timestamp' in e: e['timestamp'] = round(e['timestamp'], 2)
                        if 'total_length' in e: e['total_length'] = round(e['total_length'], 2)
                        if 'play_ratio' in e: e['play_ratio'] = round(e['play_ratio'], 2)

            with open(path, "w") as f:
                json.dump(data, f, indent=4)
        
        self._stats_buffer.clear()

    def get_play_counts(self, username: str) -> Dict[str, int]:
        path = self._get_user_stats_path(username)
        counts = {}
        if not os.path.exists(path):
            return counts
            
        with open(path, "r") as f:
            try:
                data = json.load(f)
            except:
                return counts
                
        for session in data.get("sessions", []):
            for event in session.get("events", []):
                if event.get("event_type") == "listen" or event.get("event_type") == "complete":
                    ratio = event.get("play_ratio", 0)
                    if ratio > 0.25:
                        song = event.get("song_filename")
                        counts[song] = counts.get(song, 0) + 1
        return counts
            
    # --- Favorites ---
    
    def get_favorites(self, username: str):
        user = self.get_user(username)
        if not user:
            return []
        return user.get("favorites", [])
        
    def add_favorite(self, username: str, song_filename: str, session_id: str):
        user = self.get_user(username)
        if not user: return False
        
        # 1. Update user profile
        favs = user.get("favorites", [])
        if song_filename not in favs:
            favs.append(song_filename)
            user["favorites"] = favs
            self._save_user(username, user)
            
        # 2. Log event
        # Create a synthetic stats entry for the favorite event
        entry = StatsEntry(
            session_id=session_id,
            song_filename=song_filename,
            duration_played=0,
            event_type='favorite',
            timestamp=time.time()
        )
        self.append_stats(username, entry)
            
        return True

    def remove_favorite(self, username: str, song_filename: str):
        user = self.get_user(username)
        if not user: return False
        
        # 1. Update user profile
        favs = user.get("favorites", [])
        if song_filename in favs:
            favs.remove(song_filename)
            user["favorites"] = favs
            self._save_user(username, user)
            
        # 2. Remove from history (stats)
        # We need to flush first to ensure everything is on disk
        self.flush_stats()
        
        stats_path = self._get_user_stats_path(username)
        if os.path.exists(stats_path):
            with open(stats_path, "r") as f:
                try:
                    data = json.load(f)
                except:
                    return True # Corrupted, whatever

            modified = False
            if "sessions" in data:
                for session in data["sessions"]:
                    original_len = len(session["events"])
                    # Remove favorite events for this song
                    session["events"] = [
                        e for e in session["events"] 
                        if not (e["event_type"] == "favorite" and e["song_filename"] == song_filename)
                    ]
                    if len(session["events"]) != original_len:
                        modified = True
            
            if modified:
                with open(stats_path, "w") as f:
                    json.dump(data, f, indent=4)

        return True

    # --- Suggest Less ---

    def get_suggest_less(self, username: str):
        user = self.get_user(username)
        if not user:
            return []
        return user.get("suggest_less", [])

    def add_suggest_less(self, username: str, song_filename: str):
        user = self.get_user(username)
        if not user: return False
        
        sl = user.get("suggest_less", [])
        if song_filename not in sl:
            sl.append(song_filename)
            user["suggest_less"] = sl
            self._save_user(username, user)
        return True

    def remove_suggest_less(self, username: str, song_filename: str):
        user = self.get_user(username)
        if not user: return False
        
        sl = user.get("suggest_less", [])
        if song_filename in sl:
            sl.remove(song_filename)
            user["suggest_less"] = sl
            self._save_user(username, user)
        return True
        
    # --- Playlists ---
    
    def get_playlists(self, username: str):
        playlists_path = self._get_user_playlists_path(username)
        
        # Migration: if separate file doesn't exist, check user profile
        if not os.path.exists(playlists_path):
            user = self.get_user(username)
            if user and "playlists" in user:
                # Migrate existing playlists
                raw_playlists = user["playlists"]
                migrated = []
                for p in raw_playlists:
                    # Convert simple filename list to object list if needed
                    songs = []
                    for s in p.get("songs", []):
                        if isinstance(s, str):
                            songs.append({"filename": s, "added_at": time.time()})
                        else:
                            songs.append(s)
                    migrated.append({
                        "id": p.get("id", str(uuid.uuid4())),
                        "name": p.get("name", "Untitled"),
                        "songs": songs
                    })
                
                with open(playlists_path, "w") as f:
                    json.dump(migrated, f, indent=4)
                
                # Remove from user profile to finalize migration
                del user["playlists"]
                self._save_user(username, user)
                return migrated
            return []

        with open(playlists_path, "r") as f:
            try:
                return json.load(f)
            except:
                return []

    def _save_playlists(self, username: str, playlists: List[dict]):
        with open(self._get_user_playlists_path(username), "w") as f:
            json.dump(playlists, f, indent=4)
        
    def create_playlist(self, username: str, name: str):
        playlists = self.get_playlists(username)
        
        new_playlist = {
            "id": str(uuid.uuid4()),
            "name": name,
            "songs": []
        }
        
        playlists.append(new_playlist)
        self._save_playlists(username, playlists)
        return new_playlist
        
    def delete_playlist(self, username: str, playlist_id: str):
        playlists = self.get_playlists(username)
        original_len = len(playlists)
        playlists = [p for p in playlists if p["id"] != playlist_id]
        
        if len(playlists) != original_len:
            self._save_playlists(username, playlists)
            return True
        return False
        
    def add_song_to_playlist(self, username: str, playlist_id: str, song_filename: str):
        playlists = self.get_playlists(username)
        for p in playlists:
            if p["id"] == playlist_id:
                # Check if already in playlist (by filename)
                if not any(s["filename"] == song_filename for s in p["songs"]):
                    p["songs"].append({
                        "filename": song_filename,
                        "added_at": time.time()
                    })
                    self._save_playlists(username, playlists)
                return True
        return False
        
    def remove_song_from_playlist(self, username: str, playlist_id: str, song_filename: str):
        playlists = self.get_playlists(username)
        for p in playlists:
            if p["id"] == playlist_id:
                original_len = len(p["songs"])
                p["songs"] = [s for s in p["songs"] if s["filename"] != song_filename]
                if len(p["songs"]) != original_len:
                    self._save_playlists(username, playlists)
                return True
        return False

user_service = UserService()
