import json
import os
import uuid
from passlib.context import CryptContext
from settings import settings
from models import StatsEntry, Playlist

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

class UserService:
    def __init__(self):
        if not os.path.exists(settings.USERS_DIR):
            os.makedirs(settings.USERS_DIR)

    def _get_user_path(self, username: str) -> str:
        return os.path.join(settings.USERS_DIR, f"{username}.json")

    def _get_user_stats_path(self, username: str) -> str:
        return os.path.join(settings.USERS_DIR, f"{username}_stats.json")

    def get_user(self, username: str):
        path = self._get_user_path(username)
        if not os.path.exists(path):
            return None
        with open(path, "r") as f:
            return json.load(f)
            
    def _save_user(self, username: str, data: dict):
        with open(self._get_user_path(username), "w") as f:
            json.dump(data, f, indent=4)

    def create_user(self, username: str, password: str):
        if self.get_user(username):
            return False, "User already exists"
        
        hashed_password = pwd_context.hash(password)
        user_data = {
            "username": username,
            "password": hashed_password,
            "created_at": str(os.path.getctime(settings.USERS_DIR)), # Dummy timestamp
            "favorites": [],
            "playlists": []
        }
        
        self._save_user(username, user_data)
            
        # Init stats file
        with open(self._get_user_stats_path(username), "w") as f:
            json.dump({"sessions": [], "total_play_time": 0}, f, indent=4)
            
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
        
        # Rename files
        old_path = self._get_user_path(current_username)
        new_path = self._get_user_path(new_username)
        old_stats = self._get_user_stats_path(current_username)
        new_stats = self._get_user_stats_path(new_username)
        
        user["username"] = new_username
        
        # Write new file first
        with open(new_path, "w") as f:
            json.dump(user, f, indent=4)
            
        if os.path.exists(old_stats):
            os.rename(old_stats, new_stats)
        else:
             with open(new_stats, "w") as f:
                json.dump({"sessions": [], "total_play_time": 0}, f, indent=4)

        # Remove old file
        os.remove(old_path)
        
        return True, "Username updated"

    def append_stats(self, username: str, stats: StatsEntry):
        path = self._get_user_stats_path(username)
        data = {"sessions": [], "total_play_time": 0}
        
        if os.path.exists(path):
            with open(path, "r") as f:
                try:
                    data = json.load(f)
                except:
                    pass # Reset if corrupted
        
        if "events" not in data:
            data["events"] = []
            
        data["events"].append(stats.dict())

        with open(path, "w") as f:
            json.dump(data, f, indent=4)
            
    # --- Favorites ---
    
    def get_favorites(self, username: str):
        user = self.get_user(username)
        if not user:
            return []
        return user.get("favorites", [])
        
    def add_favorite(self, username: str, song_filename: str):
        user = self.get_user(username)
        if not user: return False
        
        favs = user.get("favorites", [])
        if song_filename not in favs:
            favs.append(song_filename)
            user["favorites"] = favs
            self._save_user(username, user)
        return True

    def remove_favorite(self, username: str, song_filename: str):
        user = self.get_user(username)
        if not user: return False
        
        favs = user.get("favorites", [])
        if song_filename in favs:
            favs.remove(song_filename)
            user["favorites"] = favs
            self._save_user(username, user)
        return True
        
    # --- Playlists ---
    
    def get_playlists(self, username: str):
        user = self.get_user(username)
        if not user: return []
        return user.get("playlists", [])
        
    def create_playlist(self, username: str, name: str):
        user = self.get_user(username)
        if not user: return None
        
        new_playlist = {
            "id": str(uuid.uuid4()),
            "name": name,
            "songs": []
        }
        
        playlists = user.get("playlists", [])
        playlists.append(new_playlist)
        user["playlists"] = playlists
        self._save_user(username, user)
        return new_playlist
        
    def delete_playlist(self, username: str, playlist_id: str):
        user = self.get_user(username)
        if not user: return False
        
        playlists = user.get("playlists", [])
        user["playlists"] = [p for p in playlists if p["id"] != playlist_id]
        self._save_user(username, user)
        return True
        
    def add_song_to_playlist(self, username: str, playlist_id: str, song_filename: str):
        user = self.get_user(username)
        if not user: return False
        
        playlists = user.get("playlists", [])
        for p in playlists:
            if p["id"] == playlist_id:
                if song_filename not in p["songs"]:
                    p["songs"].append(song_filename)
                    self._save_user(username, user)
                return True
        return False
        
    def remove_song_from_playlist(self, username: str, playlist_id: str, song_filename: str):
        user = self.get_user(username)
        if not user: return False
        
        playlists = user.get("playlists", [])
        for p in playlists:
            if p["id"] == playlist_id:
                if song_filename in p["songs"]:
                    p["songs"].remove(song_filename)
                    self._save_user(username, user)
                return True
        return False

user_service = UserService()
