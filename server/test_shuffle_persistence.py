import os
import tempfile

# Setup env BEFORE any other imports to prevent settings.py from failing
os.environ["GRUSONGS_TESTING"] = "true"
test_base = tempfile.mkdtemp()
os.environ["MUSIC_DIR"] = os.path.join(test_base, "music")
os.environ["USERS_DIR"] = os.path.join(test_base, "users")
os.environ["BACKUPS_DIR"] = os.path.join(test_base, "backups")

import json
import shutil
from user_service import UserService
from models import StatsEntry
import time

def test_shuffle_persistence():
    # Setup
    username = "testuser_shuffle"
    test_users_dir = os.environ["USERS_DIR"]
    os.makedirs(test_users_dir, exist_ok=True)
    
    from database_manager import db_manager
    db_manager.init_global_dbs()
    
    try:
        service = UserService()
        service.create_user(username, "password123")
        
        # 1. Test initial state
        summary = service.get_stats_summary(username)
        assert "shuffle_state" in summary
        assert summary["shuffle_state"]["history"] == []
        
        # 2. Test updating shuffle state via explicit call
        new_state = {
            "config": {"enabled": True, "anti_repeat_enabled": False},
            "history": ["song1.mp3", "song2.mp3"]
        }
        service.update_shuffle_state(username, new_state)
        
        summary = service.get_stats_summary(username)
        assert summary["shuffle_state"]["config"]["enabled"] == True
        assert summary["shuffle_state"]["config"]["anti_repeat_enabled"] == False
        
        # Handle the new history format (list of dicts)
        history = summary["shuffle_state"]["history"]
        if history and isinstance(history[0], dict):
            history_filenames = [h["filename"] for h in history]
        else:
            history_filenames = history
            
        assert "song1.mp3" in history_filenames
        assert "song2.mp3" in history_filenames
        
        # 3. Test appending stats updates history
        stats = StatsEntry(
            session_id="session1",
            song_filename="song3.mp3",
            duration_played=120.0,
            total_length=200.0,
            event_type="complete",
            timestamp=time.time()
        )
        service.append_stats(username, stats)
        
        summary = service.get_stats_summary(username)
        history = summary["shuffle_state"]["history"]
        first_song = history[0]["filename"] if isinstance(history[0], dict) else history[0]
        assert first_song == "song3.mp3"
        
        # 4. Test history limit
        service.update_shuffle_state(username, {"config": {"history_limit": 2}})
        stats = StatsEntry(
            session_id="session1",
            song_filename="song4.mp3",
            duration_played=120.0,
            total_length=200.0,
            event_type="complete",
            timestamp=time.time()
        )
        service.append_stats(username, stats)
        summary = service.get_stats_summary(username)
        assert len(summary["shuffle_state"]["history"]) <= 2
        
        history = summary["shuffle_state"]["history"]
        first_song = history[0]["filename"] if isinstance(history[0], dict) else history[0]
        assert first_song == "song4.mp3"

        print("Backend shuffle persistence tests passed!")
        
    finally:
        if os.path.exists(test_base):
            shutil.rmtree(test_base)

if __name__ == "__main__":
    test_shuffle_persistence()
