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

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from database_manager import db_manager
from user_service import user_service
from models import StatsEntry

def test_fun_stats_thresholds():
    username = "threshold_user"
    db_manager.init_global_dbs()
    user_service.create_user(username, "pass")
    
    mock_songs = [
        {"filename": "song1.mp3", "title": "Song One", "artist": "Artist A", "duration": 100.0}
    ]
    
    with patch("user_service.music_service.list_songs", return_value=mock_songs), \
         patch("user_service.music_service.get_song_duration", return_value=100.0):
        
        # 1. Test "Actually Played" threshold (0.20)
        # Play 15s of a 100s song (ratio 0.15) -> Should NOT count as played
        user_service.append_stats(username, StatsEntry(
            session_id="s1", song_filename="song1.mp3", duration_played=15.0,
            total_length=100.0,
            event_type="listen", timestamp=time.time()
        ))
        
        # Play 25s of a 100s song (ratio 0.25) -> Should count as played
        user_service.append_stats(username, StatsEntry(
            session_id="s2", song_filename="song1.mp3", duration_played=25.0,
            total_length=100.0,
            event_type="listen", timestamp=time.time() - 100
        ))
        
        user_service.flush_stats()
        res = user_service.get_fun_stats(username)
        stats = {s["id"]: s for s in res["stats"]}
        
        # unique_songs should be 1 (only the 25s play counted)
        assert stats["unique_songs"]["value"] == "1"
        # total_songs_played should be 1
        assert stats["total_songs_played"]["value"] == "1"
        # total_time should be 40s
        assert stats["total_time"]["value"] == "0h 0m" 
        
        # 2. Test "Skip" threshold (0.90)
        # Clear stats for a clean skip test
        # We'll just use a new user
        username2 = "skip_user"
        user_service.create_user(username2, "pass")
        
        # Scenario A: Explicit skip at 95% (0.95) -> Should NOT count as skip
        user_service.append_stats(username2, StatsEntry(
            session_id="s3", song_filename="song1.mp3", duration_played=95.0,
            total_length=100.0,
            event_type="skip", timestamp=time.time()
        ))
        
        # Scenario B: Explicit skip at 85% (0.85) -> SHOULD count as skip
        user_service.append_stats(username2, StatsEntry(
            session_id="s4", song_filename="song1.mp3", duration_played=85.0,
            total_length=100.0,
            event_type="skip", timestamp=time.time() - 100
        ))
        
        # Scenario C: Low ratio (0.15) -> SHOULD count as skip
        user_service.append_stats(username2, StatsEntry(
            session_id="s5", song_filename="song1.mp3", duration_played=15.0,
            total_length=100.0,
            event_type="listen", timestamp=time.time() - 200
        ))

        user_service.flush_stats()
        res2 = user_service.get_fun_stats(username2)
        stats2 = {s["id"]: s for s in res2["stats"]}
        
        # total skips should be 2 (Scenario B and C)
        assert stats2["skips"]["value"] == "2"
        
        print("✅ Fun Stats threshold logic (0.20 play / 0.90 skip) verified!")

if __name__ == "__main__":
    try:
        test_fun_stats_thresholds()
    finally:
        shutil.rmtree(TEST_DIR)