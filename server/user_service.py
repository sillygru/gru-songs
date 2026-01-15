import os
import time
import uuid
import json
import hashlib
import bcrypt
import logging
from typing import Dict, List, Optional, Any
from collections import defaultdict
from sqlmodel import Session, select, func, delete

from settings import settings
from services import music_service
from database_manager import db_manager
from db_models import GlobalUser, Upload, UserData, Favorite, SuggestLess, Playlist, PlaylistSong, PlaySession, PlayEvent
from models import StatsEntry

logger = logging.getLogger("uvicorn.error")

class UserService:
    def __init__(self):
        # Ensure global DBs exist
        db_manager.init_global_dbs()
        self.discord_queue = None
        self._stats_buffer = defaultdict(list) # username -> list of StatsEntry
        self._last_flush = time.time()
        self._is_flushing = False

    def set_discord_queue(self, queue):
        self.discord_queue = queue

    def log_to_discord(self, message: str):
        if self.discord_queue:
            self.discord_queue.put(message)

    def _get_final_stats_path(self, username: str):
        return os.path.join(settings.USERS_DIR, f"{username}_final_stats.json")

    def _get_summary_no_flush(self, username: str) -> Dict[str, Any]:
        final_path = self._get_final_stats_path(username)
        summary = {"total_play_time": 0, "total_sessions": 0, "shuffle_state": {"config": {}, "history": []}}
        if os.path.exists(final_path):
            try:
                with open(final_path, "r") as f:
                    data = json.load(f)
                    summary.update(data)
            except: pass
        # Ensure shuffle_state exists
        if "shuffle_state" not in summary:
            summary["shuffle_state"] = {"config": {}, "history": []}
        return summary

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
            json.dump({
                "total_play_time": 0, 
                "total_sessions": 0,
                "shuffle_state": {"config": {}, "history": []}
            }, f, indent=4)
            
        self.log_to_discord(f"🆕 New user registered: **{username}**")
        return True, "User created"

    def authenticate_user(self, username: str, password: str):
        user = self.get_user(username)
        if not user:
            return False
        is_valid = self._verify_password(password, user["password"])
        if is_valid:
            self.log_to_discord(f"🔑 **{username}** logged in")
        return is_valid

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
        # Flush stats before renaming files to avoid data loss
        self.flush_stats()

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

        self.log_to_discord(f"🆔 **{current_username}** changed username to **{new_username}**")
        return True, "Username updated"

    # --- Statistics ---

    def append_stats(self, username: str, stats: StatsEntry):
        if stats.duration_played <= 0 and stats.event_type != 'favorite':
            return

        # Add to memory buffer for periodic flush
        self._stats_buffer[username].append(stats)
            
        # Log to discord for visibility (Immediate feedback)
        total_length = music_service.get_song_duration(stats.song_filename)
        ratio = 0.0
        if total_length > 0:
            ratio = stats.duration_played / total_length

        emoji = "🎵"
        if stats.event_type == 'favorite': emoji = "❤️"
        elif stats.event_type == 'complete': emoji = "✅"
        elif stats.event_type == 'listen': emoji = "🎧"

        ratio_pct = round(ratio * 100)
        fg_val = stats.foreground_duration if isinstance(stats.foreground_duration, (int, float)) else 0
        bg_val = stats.background_duration if isinstance(stats.background_duration, (int, float)) else 0
        
        log_msg = (
            f"{emoji} **{username}** | `{stats.song_filename}`\n"
            f"> **Action:** {stats.event_type.upper()}\n"
            f"> **Progress:** {round(stats.duration_played, 1)}s / {round(total_length, 1)}s ({ratio_pct}%)\n"
        )
        
        if fg_val > 0 or bg_val > 0:
            log_msg += f"> **Activity:** 📱 FG: {round(fg_val, 1)}s | 🎧 BG: {round(bg_val, 1)}s\n"
        
        log_msg += (
            f"> **Device:** `{stats.platform or 'unknown'}`\n"
            f"> **Session:** `{stats.session_id[:8]}...`"
        )

        self.log_to_discord(log_msg)

    def get_stats_summary(self, username: str) -> Dict[str, Any]:
        # Flush to ensure JSON is up to date
        self.flush_stats()
        return self._get_summary_no_flush(username)

    def update_shuffle_state(self, username: str, shuffle_state_data: Dict[str, Any]):
        # Flush first to ensure we don't overwrite pending updates
        self.flush_stats()

        final_path = self._get_final_stats_path(username)
        summary_data = self._get_summary_no_flush(username)
        
        # Deep merge/update shuffle state
        current_shuffle = summary_data.get("shuffle_state", {})
        
        # Update config
        if "config" in shuffle_state_data:
            current_config = current_shuffle.get("config", {})
            current_config.update(shuffle_state_data["config"])
            current_shuffle["config"] = current_config
            
        # Update history with timestamp awareness
        if "history" in shuffle_state_data:
            new_history = shuffle_state_data["history"]
            # Handle list of strings (legacy) or list of dicts (new)
            if new_history and isinstance(new_history[0], str):
                # Convert legacy incoming to timestamped
                current_time = time.time()
                new_history = [{"filename": f, "timestamp": current_time - i} for i, f in enumerate(new_history)]
            
            # Merge logic: if remote has newer history for a song, we keep it, but for simplicity
            # since history is a chronological list, we trust the incoming sync as the "latest" state.
            current_shuffle["history"] = new_history
            
        summary_data["shuffle_state"] = current_shuffle
        
        with open(final_path, "w") as f:
            json.dump(summary_data, f, indent=4)
        return summary_data

    def flush_stats(self):
        if self._is_flushing:
            return
            
        # Quick check if there's anything to flush
        if not any(self._stats_buffer.values()):
            self._stats_buffer.clear() # Clean up empty defaultdict entries
            return

        self._is_flushing = True
        try:
            start_time = time.time()
            # Snapshot the buffer to avoid size change issues and only take non-empty lists
            buffer_snapshot = {u: evs for u, evs in self._stats_buffer.items() if evs}
            self._stats_buffer.clear()

            if not buffer_snapshot:
                return

            users_processed = list(buffer_snapshot.keys())
            total_events = sum(len(evs) for evs in buffer_snapshot.values())
            
            # Detailed breakdown for logging/discord
            breakdown = []

            for username, events in buffer_snapshot.items():
                # Track unique songs in this flush for this user
                songs_flushed = [f"`{e.song_filename}`" for e in events]
                # Unique-ish summary
                song_summary = ", ".join(list(set(songs_flushed))[:10])
                if len(set(songs_flushed)) > 10:
                    song_summary += " ..."
                
                breakdown.append(f"**{username}**: {len(events)} events ({song_summary})")
                
                # 1. Update SQL Database
                try:
                    with Session(db_manager.get_user_stats_engine(username)) as session:
                        for stats in events:
                            # Session logic
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
                            total_length = music_service.get_song_duration(stats.song_filename)
                            ratio = (stats.duration_played / total_length) if total_length > 0 else 0.0
                            
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
                except Exception as e:
                    logger.error(f"Failed to flush SQL stats for {username}: {e}")

                # 2. Update Final Stats JSON
                final_path = self._get_final_stats_path(username)
                try:
                    summary_data = self._get_summary_no_flush(username)
                    
                    # Ensure all keys exist
                    for key in ["total_play_time", "total_sessions", "total_background_playtime", 
                               "total_foreground_playtime", "total_songs_played", 
                               "total_songs_played_ratio_over_025", "total_skipped"]:
                        if key not in summary_data:
                            summary_data[key] = 0

                    if "platform_usage" not in summary_data:
                        summary_data["platform_usage"] = {}

                    processed_sessions = set()

                    for stats in events:
                        # Metrics
                        summary_data["total_play_time"] = round(summary_data["total_play_time"] + stats.duration_played, 2)
                        
                        fg = stats.foreground_duration if isinstance(stats.foreground_duration, (int, float)) else 0
                        bg = stats.background_duration if isinstance(stats.background_duration, (int, float)) else 0
                        summary_data["total_foreground_playtime"] = round(summary_data["total_foreground_playtime"] + fg, 2)
                        summary_data["total_background_playtime"] = round(summary_data["total_background_playtime"] + bg, 2)

                        total_length = music_service.get_song_duration(stats.song_filename)
                        ratio = (stats.duration_played / total_length) if total_length > 0 else 0.0

                        # A song is considered "played" if:
                        # 1. It's a natural completion/listen flush
                        # 2. It was skipped but already played more than 80% (fake skip)
                        # 3. It was listened to for more than 20%
                        is_meaningful_play = (
                            stats.event_type in ['complete', 'listen'] or
                            ratio > 0.8 or
                            (stats.event_type != 'favorite' and ratio > 0.2)
                        )

                        if stats.event_type != 'favorite' and is_meaningful_play:
                            summary_data["total_songs_played"] += 1
                        
                        # A song is considered "skipped" ONLY if it's a skip event with low ratio
                        if stats.event_type == 'skip' and ratio < 0.2:
                            summary_data["total_skipped"] += 1

                        # Shuffle history update: Significant plays or completions
                        if is_meaningful_play:
                            shuffle_state = summary_data.get("shuffle_state", {})
                            history = shuffle_state.get("history", [])
                            
                            # Clean history to work with timestamps
                            new_entry = {"filename": stats.song_filename, "timestamp": stats.timestamp}
                            
                            # Remove existing entry for this song
                            history = [h for h in history if (isinstance(h, dict) and h["filename"] != stats.song_filename) or (isinstance(h, str) and h != stats.song_filename)]
                            
                            history.insert(0, new_entry)
                            
                            config = shuffle_state.get("config", {})
                            history_limit = config.get("history_limit", 50)
                            if len(history) > history_limit:
                                history = history[:history_limit]
                            
                            shuffle_state["history"] = history
                            summary_data["shuffle_state"] = shuffle_state

                        if stats.event_type != "favorite" and ratio > 0.25:
                            summary_data["total_songs_played_ratio_over_025"] += 1

                        # Session/Platform Logic
                        if stats.session_id not in processed_sessions:
                            # We only want to increment total_sessions if it's actually a NEW session
                            # Check if session already exists in SQL
                            with Session(db_manager.get_user_stats_engine(username)) as session:
                                existing_sess = session.exec(select(PlaySession).where(PlaySession.id == stats.session_id)).first()
                                if not existing_sess:
                                    summary_data["total_sessions"] += 1
                                    p = stats.platform or "unknown"
                                    summary_data["platform_usage"][p] = summary_data["platform_usage"].get(p, 0) + 1
                            processed_sessions.add(stats.session_id)
                    
                    with open(final_path, "w") as f:
                        json.dump(summary_data, f, indent=4)
                except Exception as e:
                    logger.error(f"Failed to update JSON stats for {username}: {e}")

            # Log summary
            self._last_flush = time.time()
            duration = round(time.time() - start_time, 3)
            
            summary_msg = f"📊 **Stats Flush Complete** ({duration}s)\n"
            summary_msg += f"> **Total Events:** `{total_events}`\n"
            summary_msg += "\n".join([f"> {b}" for b in breakdown])
            
            logger.info(f"Stats flush completed in {duration}s. Breakdown: {', '.join(breakdown)}")
            self.log_to_discord(summary_msg)
        finally:
            self._is_flushing = False

    def get_play_counts(self, username: str) -> Dict[str, int]:
        # Flush first to ensure DB is up to date
        self.flush_stats()

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
                
                # Log stats (immediate add to buffer)
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
            
        self.log_to_discord(f"📥 **{username}** uploaded/added: `{filename}` (Source: {source})")

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

            # Shuffle state hash
            summary = self.get_stats_summary(username)
            shuffle = summary.get("shuffle_state", {})
            hashes["shuffle"] = hashlib.md5(json.dumps(shuffle, sort_keys=True).encode()).hexdigest()
            
        return hashes

user_service = UserService()

    