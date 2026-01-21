import os
import tempfile
import sys
import time
import json
import shutil
from unittest.mock import MagicMock, patch

# Setup env
os.environ["GRUSONGS_TESTING"] = "true"
TEST_DIR = tempfile.mkdtemp()
os.environ["MUSIC_DIR"] = os.path.join(TEST_DIR, "music")
os.environ["USERS_DIR"] = os.path.join(TEST_DIR, "users")
os.environ["BACKUPS_DIR"] = os.path.join(TEST_DIR, "backups")

os.makedirs(os.environ["USERS_DIR"], exist_ok=True)
os.makedirs(os.environ["MUSIC_DIR"], exist_ok=True)

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database_manager import db_manager
from user_service import user_service
from models import StatsEntry

def test_fun_stats_logic():
    username = "fun_user"
    db_manager.init_global_dbs()
    user_service.create_user(username, "pass")
    
    # Populate metadata
    user_service.record_upload(username, "song1.mp3", title="Song One", artist="Artist A")
    user_service.record_upload(username, "song2.mp3", title="Song Two", artist="Artist B")
    
    # Mock song list
    mock_songs = [
        {"filename": "song1.mp3", "title": "Song One", "artist": "Artist A", "duration": 100.0},
        {"filename": "song2.mp3", "title": "Song Two", "artist": "Artist B", "duration": 200.0}
    ]
    
    with patch("user_service.music_service.list_songs", return_value=mock_songs), \
         patch("user_service.music_service.get_song_duration", side_effect=lambda f: 100.0 if f=="song1.mp3" else 200.0):
        
        # Add some plays
        # Song 1: 3 plays
        for i in range(3):
            user_service.append_stats(username, StatsEntry(
                session_id="sess1",
                song_filename="song1.mp3",
                duration_played=100.0,
                total_length=100.0,
                event_type="complete",
                timestamp=time.time() - (i * 86400) # One per day for streak
            ))
            
        # Song 2: 1 play
        user_service.append_stats(username, StatsEntry(
            session_id="sess1",
            song_filename="song2.mp3",
            duration_played=200.0,
            total_length=200.0,
            event_type="complete",
            timestamp=time.time()
        ))
        
        user_service.flush_stats()
        
        # Fetch fun stats
        res = user_service.get_fun_stats(username)
        
        assert "stats" in res
        stats = res["stats"]
        
        # Verify some key stats
        label_map = {s["id"]: s for s in stats}
        
        assert "top_artist" in label_map
        assert label_map["top_artist"]["value"] == "Artist A"
        
        assert "top_song" in label_map
        assert label_map["top_song"]["value"] == "Song One"
        
        assert "unique_songs" in label_map
        assert label_map["unique_songs"]["value"] == "2"
        
        assert "explorer_score" in label_map
        assert label_map["explorer_score"]["value"] == "100%" # 2/2 songs played
        
        print("✅ Fun Stats logic verified!")

if __name__ == "__main__":
    try:
        test_fun_stats_logic()
    finally:
        shutil.rmtree(TEST_DIR)