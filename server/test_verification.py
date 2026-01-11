import sys
import os
import shutil
import tempfile
import time
from unittest.mock import MagicMock

# 1. SETUP: Create Temp Dirs
TEST_DIR = tempfile.mkdtemp()
TEST_USERS_DIR = os.path.join(TEST_DIR, "users")
TEST_MUSIC_DIR = os.path.join(TEST_DIR, "music")
os.makedirs(TEST_USERS_DIR, exist_ok=True)
os.makedirs(TEST_MUSIC_DIR, exist_ok=True)

print(f"Test running in: {TEST_DIR}")

# 2. Add server dir to path
server_path = os.path.dirname(os.path.abspath(__file__))
sys.path.append(server_path)

# 3. Import settings and Override
from settings import settings
settings.USERS_DIR = TEST_USERS_DIR
settings.MUSIC_DIR = TEST_MUSIC_DIR
settings.DOWNLOADED_DIR = os.path.join(TEST_MUSIC_DIR, "downloaded")
os.makedirs(settings.DOWNLOADED_DIR, exist_ok=True)

# 4. Mock music_service BEFORE importing user_service
# Because user_service imports music_service
import services
services.music_service = MagicMock()
services.music_service.get_song_duration.return_value = 180.0 # Fake 3 min song

# 5. Import Services
from database_manager import db_manager
# Force re-init of db_manager with new settings
db_manager.users_dir = TEST_USERS_DIR

from user_service import user_service
from models import StatsEntry

def test_everything():
    try:
        print("\n--- 1. Testing User Creation ---")
        username = "testuser"
        password = "password123"
        success, msg = user_service.create_user(username, password)
        if not success:
             raise Exception(f"Failed to create user: {msg}")
        print(f"✅ User created: {msg}")

        # Verify files exist
        expected_files = [
            "global_users.db",
            "uploads.db",
            f"{username}_data.db",
            f"{username}_playlists.db",
            f"{username}_stats.db",
            f"{username}_final_stats.json"
        ]
        for f in expected_files:
            if not os.path.exists(os.path.join(TEST_USERS_DIR, f)):
                raise Exception(f"Missing expected file: {f}")
        print("✅ All DB files created.")

        if not user_service.authenticate_user(username, password):
             raise Exception("Authentication failed")
        print("✅ Authentication successful.")

        print("\n--- 2. Testing Stats & Speed ---")
        session_id = "sess_1"
        song = "song1.mp3"
        
        # Add a stat
        stats = StatsEntry(
            session_id=session_id,
            song_filename=song,
            duration_played=180.0,
            event_type="complete",
            timestamp=time.time(),
            platform="ios",
            foreground_duration=100.0,
            background_duration=80.0
        )
        user_service.append_stats(username, stats)
        print("✅ Added stats entry (complete listen).")

        # Verify Play Counts (Should be 1, since 180/180 ratio = 1.0 > 0.25)
        counts = user_service.get_play_counts(username)
        if counts.get(song) != 1:
            raise Exception(f"Expected play count 1, got {counts.get(song)}")
        print("✅ Play count correct.")

        # Add partial listen (ratio < 0.25)
        stats_skip = StatsEntry(
            session_id=session_id,
            song_filename="song2.mp3",
            duration_played=10.0,
            event_type="skip",
            timestamp=time.time(),
            platform="ios"
        )
        user_service.append_stats(username, stats_skip)
        
        counts = user_service.get_play_counts(username)
        if counts.get("song2.mp3", 0) != 0:
             raise Exception("Partial listen should not count.")
        print("✅ Partial listen correctly ignored in play counts.")

        # Verify Final Stats JSON updated
        import json
        with open(os.path.join(TEST_USERS_DIR, f"{username}_final_stats.json"), "r") as f:
            summary = json.load(f)
            if summary["total_play_time"] != 190.0:
                 raise Exception(f"Expected total_play_time 190.0, got {summary['total_play_time']}")
        print("✅ Final stats JSON updated.")

        print("\n--- 3. Testing Playlists ---")
        pl = user_service.create_playlist(username, "My Jam")
        if not pl: raise Exception("Failed to create playlist")
        print(f"✅ Playlist created: {pl['id']}")

        if not user_service.add_song_to_playlist(username, pl['id'], "song1.mp3"):
            raise Exception("Failed to add song")
        
        playlists = user_service.get_playlists(username)
        if len(playlists) != 1 or len(playlists[0]["songs"]) != 1:
            raise Exception("Playlist state incorrect")
        print("✅ Song added to playlist.")

        if not user_service.remove_song_from_playlist(username, pl['id'], "song1.mp3"):
            raise Exception("Failed to remove song")
        
        playlists = user_service.get_playlists(username)
        if len(playlists[0]["songs"]) != 0:
             raise Exception("Song not removed")
        print("✅ Song removed from playlist.")

        print("\n--- 4. Testing Username Update (Renaming) ---")
        new_username = "cooluser"
        success, msg = user_service.update_username(username, new_username)
        if not success:
            raise Exception(f"Failed to update username: {msg}")
        
        # Verify old files gone, new files exist
        if os.path.exists(os.path.join(TEST_USERS_DIR, f"{username}_data.db")):
            raise Exception("Old DB file still exists!")
        if not os.path.exists(os.path.join(TEST_USERS_DIR, f"{new_username}_data.db")):
            raise Exception("New DB file missing!")
        
        # Verify login with new username
        if not user_service.authenticate_user(new_username, password):
            raise Exception("Auth with new username failed")
        print("✅ Username updated and files renamed successfully.")

        print("\n--- 5. Testing Global Uploads ---")
        user_service.record_upload(new_username, "upload1.mp3", title="My Upload")
        uploader = user_service.get_uploader("upload1.mp3")
        if uploader != new_username:
            raise Exception(f"Expected uploader {new_username}, got {uploader}")
        print("✅ Upload recorded globally.")

        print("\n✅ ALL TESTS PASSED")

    except Exception as e:
        print(f"\n❌ TEST FAILED: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        print("Cleaning up...")
        try:
            shutil.rmtree(TEST_DIR)
        except:
            pass

if __name__ == "__main__":
    test_everything()
