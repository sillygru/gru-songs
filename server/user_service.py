import os
import time
import uuid
import json
import hashlib
import bcrypt
from typing import Dict, List, Optional, Any
from sqlmodel import Session, select, func, delete

from settings import settings
from services import music_service
from database_manager import db_manager
from db_models import GlobalUser, Upload, UserData, Favorite, SuggestLess, Playlist, PlaylistSong, PlaySession, PlayEvent
from models import StatsEntry

class UserService:
    def __init__(self):
        # Ensure global DBs exist
        db_manager.init_global_dbs()

    def _get_final_stats_path(self, username: str):
        return os.path.join(settings.USERS_DIR, f"{username}_final_stats.json")

    def _hash_password(self, password: str) -> str:
        salt = bcrypt.gensalt()
        hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
        return hashed.decode('utf-8')

    def _verify_password(self, password: str, hashed: str) -> bool:
        try:
            return bcrypt.checkpw(password.encode('utf-8'), hashed.encode('utf-8'))
        except Exception:
            return False

    # --- User Management ---

    def get_user(self, username: str) -> Optional[dict]:
        path = os.path.join(settings.USERS_DIR, f"{username}_data.db")
        if not os.path.exists(path):
            return None

        try:
            with Session(db_manager.get_user_data_engine(username)) as session:
                user = session.exec(select(UserData).where(UserData.username == username)).first()
                if not user: return None
                
                favorites = session.exec(select(Favorite)).all()
                suggest_less = session.exec(select(SuggestLess)).all()
                
                return {
                    "username": user.username,
                    "password": user.password_hash,
                    "created_at": str(user.created_at),
                    "favorites": [f.filename for f in favorites],
                    "suggest_less": [s.filename for s in suggest_less]
                }
        except Exception:
            return None
            
    def create_user(self, username: str, password: str):
        with Session(db_manager.get_global_users_engine()) as session:
            existing = session.exec(select(GlobalUser).where(GlobalUser.username == username)).first()
            if existing:
                return False, "User already exists"
            
            # 1. Add to Global DB
            new_global = GlobalUser(username=username, created_at=time.time())
            session.add(new_global)
            session.commit()

        # 2. Init [username]_data.db
        db_manager.init_user_dbs(username) 
        
        hashed_password = self._hash_password(password)
        with Session(db_manager.get_user_data_engine(username)) as session:
            ud = UserData(username=username, password_hash=hashed_password, created_at=time.time())
            session.add(ud)
            session.commit()

        # 3. Create empty final stats JSON
        with open(self._get_final_stats_path(username), "w") as f:
            json.dump({"total_play_time": 0, "total_sessions": 0}, f, indent=4)
            
        return True, "User created"

    def authenticate_user(self, username: str, password: str):
        user = self.get_user(username)
        if not user:
            return False
        return self._verify_password(password, user["password"])

    def update_password(self, username: str, old_password: str, new_password: str):
        user = self.get_user(username)
        if not user:
            return False, "User not found"
        
        if not self._verify_password(old_password, user["password"]):
            return False, "Invalid old password"
        
        with Session(db_manager.get_user_data_engine(username)) as session:
            db_user = session.exec(select(UserData).where(UserData.username == username)).first()
            if db_user:
                db_user.password_hash = self._hash_password(new_password)
                session.add(db_user)
                session.commit()
            
        return True, "Password updated"

    def update_username(self, current_username: str, new_username: str):
        # 1. Check Global DB
        with Session(db_manager.get_global_users_engine()) as session:
            if session.exec(select(GlobalUser).where(GlobalUser.username == new_username)).first():
                return False, "Username already taken"
            
            # Get old global record
            old_global = session.exec(select(GlobalUser).where(GlobalUser.username == current_username)).first()
            if not old_global:
                return False, "User not found"
                
            # Rename in Global DB
            session.delete(old_global)
            session.add(GlobalUser(username=new_username, created_at=old_global.created_at, stats_summary_json=old_global.stats_summary_json))
            session.commit()

        # 2. Rename Files
        files_to_rename = [
            (f"{current_username}_data.db", f"{new_username}_data.db"),
            (f"{current_username}_playlists.db", f"{new_username}_playlists.db"),
            (f"{current_username}_stats.db", f"{new_username}_stats.db"),
            (f"{current_username}_final_stats.json", f"{new_username}_final_stats.json")
        ]
        
        for old, new in files_to_rename:
            old_p = os.path.join(settings.USERS_DIR, old)
            new_p = os.path.join(settings.USERS_DIR, new)
            if os.path.exists(old_p):
                os.rename(old_p, new_p)

        # 3. Update internal username field in [new_user]_data.db
        with Session(db_manager.get_user_data_engine(new_username)) as session:
            u_data = session.exec(select(UserData)).first() # Should be only one
            if u_data:
                u_data.username = new_username
                session.add(u_data)
                session.commit()

        return True, "Username updated"

    # --- Statistics ---

    def append_stats(self, username: str, stats: StatsEntry):
        if stats.duration_played <= 0 and stats.event_type != 'favorite':
            return

        total_length = music_service.get_song_duration(stats.song_filename)
        ratio = 0.0
        if total_length > 0:
            ratio = stats.duration_played / total_length
            
        with Session(db_manager.get_user_stats_engine(username)) as session:
            # Session Logic
            db_session = session.exec(select(PlaySession).where(PlaySession.id == stats.session_id)).first()
            if not db_session:
                db_session = PlaySession(
                    id=stats.session_id,
                    start_time=stats.timestamp,
                    end_time=stats.timestamp,
                    platform=stats.platform or "unknown"
                )
                session.add(db_session)
            else:
                if stats.timestamp < db_session.start_time: db_session.start_time = stats.timestamp
                if stats.timestamp > db_session.end_time: db_session.end_time = stats.timestamp
                if db_session.platform == "unknown" and stats.platform and stats.platform != "unknown":
                    db_session.platform = stats.platform
                session.add(db_session)
            
            session.commit() # Ensure session ID is valid
            
            # Event Logic
            fg = stats.foreground_duration if isinstance(stats.foreground_duration, (int, float)) else None
            bg = stats.background_duration if isinstance(stats.background_duration, (int, float)) else None

            pe = PlayEvent(
                session_id=stats.session_id,
                song_filename=stats.song_filename,
                event_type=stats.event_type,
                timestamp=round(stats.timestamp, 2),
                duration_played=round(stats.duration_played, 2),
                total_length=round(total_length, 2),
                play_ratio=round(ratio, 2),
                foreground_duration=round(fg, 2) if fg is not None else None,
                background_duration=round(bg, 2) if bg is not None else None
            )
            session.add(pe)
            session.commit()
            
        # Update Final Stats JSON (Aggregated)
        final_path = self._get_final_stats_path(username)
        summary = {}
        if os.path.exists(final_path):
            try:
                with open(final_path, "r") as f:
                    summary = json.load(f)
            except: pass
            
        # Increment simple counters
        summary["total_play_time"] = summary.get("total_play_time", 0) + stats.duration_played
        summary["total_play_time"] = round(summary["total_play_time"], 2)
        
        with open(final_path, "w") as f:
            json.dump(summary, f, indent=4)

    def flush_stats(self):
        pass

    def get_play_counts(self, username: str) -> Dict[str, int]:
        # Query [username]_stats.db
        path = os.path.join(settings.USERS_DIR, f"{username}_stats.db")
        if not os.path.exists(path): return {}

        with Session(db_manager.get_user_stats_engine(username)) as session:
            # FAST: Filter in SQL now that we have numeric columns
            results = session.exec(
                select(PlayEvent.song_filename, func.count(PlayEvent.id))
                .where(PlayEvent.event_type != "favorite")
                .where(PlayEvent.play_ratio > 0.25)
                .group_by(PlayEvent.song_filename)
            ).all()
            
            return {r[0]: r[1] for r in results}
            
    # --- Favorites ---
    
    def get_favorites(self, username: str):
        with Session(db_manager.get_user_data_engine(username)) as session:
            favs = session.exec(select(Favorite)).all()
            return [f.filename for f in favs]
        
    def add_favorite(self, username: str, song_filename: str, session_id: str):
        with Session(db_manager.get_user_data_engine(username)) as session:
            if not session.exec(select(Favorite).where(Favorite.filename == song_filename)).first():
                session.add(Favorite(filename=song_filename))
                session.commit()
                
                # Log stats
                self.append_stats(username, StatsEntry(
                    session_id=session_id,
                    song_filename=song_filename,
                    duration_played=0,
                    event_type='favorite',
                    timestamp=time.time()
                ))
        return True

    def remove_favorite(self, username: str, song_filename: str):
        with Session(db_manager.get_user_data_engine(username)) as session:
            fav = session.exec(select(Favorite).where(Favorite.filename == song_filename)).first()
            if fav:
                session.delete(fav)
                session.commit()
        return True

    # --- Suggest Less ---

    def get_suggest_less(self, username: str):
        with Session(db_manager.get_user_data_engine(username)) as session:
            sl = session.exec(select(SuggestLess)).all()
            return [s.filename for s in sl]

    def add_suggest_less(self, username: str, song_filename: str):
        with Session(db_manager.get_user_data_engine(username)) as session:
            if not session.exec(select(SuggestLess).where(SuggestLess.filename == song_filename)).first():
                session.add(SuggestLess(filename=song_filename))
                session.commit()
        return True

    def remove_suggest_less(self, username: str, song_filename: str):
        with Session(db_manager.get_user_data_engine(username)) as session:
            sl = session.exec(select(SuggestLess).where(SuggestLess.filename == song_filename)).first()
            if sl:
                session.delete(sl)
                session.commit()
        return True
        
    # --- Playlists ---
    
    def get_playlists(self, username: str):
        path = os.path.join(settings.USERS_DIR, f"{username}_playlists.db")
        if not os.path.exists(path): return []
        
        with Session(db_manager.get_user_playlists_engine(username)) as session:
            playlists = session.exec(select(Playlist)).all()
            result = []
            for p in playlists:
                # Need to fetch songs explicitly or join
                # Since we are in the same DB, we can do a secondary query
                songs = session.exec(select(PlaylistSong).where(PlaylistSong.playlist_id == p.id)).all()
                result.append({
                    "id": p.id,
                    "name": p.name,
                    "songs": [{"filename": s.filename, "added_at": s.added_at} for s in songs]
                })
            return result

    def create_playlist(self, username: str, name: str):
        new_id = str(uuid.uuid4())
        with Session(db_manager.get_user_playlists_engine(username)) as session:
            pl = Playlist(id=new_id, name=name)
            session.add(pl)
            session.commit()
            return {"id": new_id, "name": name, "songs": []}
        
    def delete_playlist(self, username: str, playlist_id: str):
        with Session(db_manager.get_user_playlists_engine(username)) as session:
            pl = session.exec(select(Playlist).where(Playlist.id == playlist_id)).first()
            if pl:
                session.delete(pl)
                session.commit()
                return True
        return False
        
    def add_song_to_playlist(self, username: str, playlist_id: str, song_filename: str):
        with Session(db_manager.get_user_playlists_engine(username)) as session:
            # Check duplicates
            exists = session.exec(select(PlaylistSong).where(PlaylistSong.playlist_id == playlist_id, PlaylistSong.filename == song_filename)).first()
            if not exists:
                session.add(PlaylistSong(playlist_id=playlist_id, filename=song_filename, added_at=time.time()))
                session.commit()
                return True
        return False
        
    def remove_song_from_playlist(self, username: str, playlist_id: str, song_filename: str):
        with Session(db_manager.get_user_playlists_engine(username)) as session:
            song = session.exec(select(PlaylistSong).where(PlaylistSong.playlist_id == playlist_id, PlaylistSong.filename == song_filename)).first()
            if song:
                session.delete(song)
                session.commit()
                return True
        return False

    # --- Uploads (Global) ---

    def record_upload(self, username: str, filename: str, title: str = None, source: str = "file", original_filename: str = None, youtube_url: str = None):
        if title is None:
            title = filename.rsplit('.', 1)[0]
            
        with Session(db_manager.get_uploads_engine()) as session:
            upload = session.exec(select(Upload).where(Upload.filename == filename)).first()
            if not upload:
                upload = Upload(
                    filename=filename,
                    uploader_username=username,
                    title=title,
                    source=source,
                    original_filename=original_filename if original_filename else filename,
                    youtube_url=youtube_url,
                    timestamp=time.time()
                )
                session.add(upload)
            else:
                upload.title = title
                upload.uploader_username = username
                session.add(upload)
            session.commit()

    def get_custom_title(self, filename: str) -> str:
        with Session(db_manager.get_uploads_engine()) as session:
            upload = session.exec(select(Upload).where(Upload.filename == filename)).first()
            return upload.title if upload else None

        def get_uploader(self, filename: str) -> str:

            with Session(db_manager.get_uploads_engine()) as session:

                upload = session.exec(select(Upload).where(Upload.filename == filename)).first()

                return upload.uploader_username if upload else "Unknown"

    

    def get_sync_hashes(self, username: Optional[str]) -> Dict[str, str]:
        # Hash songs list
        songs = music_service.list_songs()
        songs_json = json.dumps(songs, sort_keys=True)
        songs_hash = hashlib.md5(songs_json.encode()).hexdigest()
        
        hashes = {
            "songs": songs_hash
        }
        
        if username:
            # Favorites hash
            favs = self.get_favorites(username)
            hashes["favorites"] = hashlib.md5(json.dumps(favs, sort_keys=True).encode()).hexdigest()
            
            # Playlists hash
            playlists = self.get_playlists(username)
            hashes["playlists"] = hashlib.md5(json.dumps(playlists, sort_keys=True).encode()).hexdigest()
            
            # Suggest less hash
            sl = self.get_suggest_less(username)
            hashes["suggest_less"] = hashlib.md5(json.dumps(sl, sort_keys=True).encode()).hexdigest()
            
        return hashes

user_service = UserService()

    