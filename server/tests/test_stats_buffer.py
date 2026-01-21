import sys
import os
import shutil
import tempfile
import time
import json
from unittest.mock import MagicMock, patch

# Setup env BEFORE any other imports to prevent settings.py from failing
os.environ["GRUSONGS_TESTING"] = "true"
TEST_DIR = tempfile.mkdtemp()
os.environ["MUSIC_DIR"] = os.path.join(TEST_DIR, "music")
os.environ["USERS_DIR"] = os.path.join(TEST_DIR, "users")
os.environ["BACKUPS_DIR"] = os.path.join(TEST_DIR, "backups")

# 1. Ensure dirs exist
TEST_USERS_DIR = os.environ["USERS_DIR"]
TEST_MUSIC_DIR = os.environ["MUSIC_DIR"]
os.makedirs(TEST_USERS_DIR, exist_ok=True)
os.makedirs(TEST_MUSIC_DIR, exist_ok=True)

print(f"Test running in: {TEST_DIR}")

# 2. Add server dir to path
server_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(server_path)

# 3. Import settings
from settings import settings

# 4. Mock services and setup
import services
services.music_service = MagicMock()
services.music_service.get_song_duration.return_value = 200.0

from database_manager import db_manager
db_manager.users_dir = TEST_USERS_DIR

from user_service import user_service
from models import StatsEntry

def test_stats_buffering_and_flushing():
    with patch("user_service.music_service.get_song_duration", return_value=200.0):
        try:
            print("\n--- 1. User Setup ---")
            username = "buffer_test_user"
            db_manager.init_global_dbs()
            user_service.create_user(username, "pass")
            
            # Verify initial state
            summary = user_service.get_stats_summary(username)
            assert summary["total_play_time"] == 0
            print("✅ User created with 0 stats.")

            print("\n--- 2. Appending Stats (Buffering) ---")
            # Mock discord queue to capture logs
            mock_queue = MagicMock()
            user_service.set_discord_queue(mock_queue)

            stat1 = StatsEntry(
                session_id="sess_abc",
                song_filename="track1.mp3",
                duration_played=120.0,
                total_length=200.0,
                event_type="complete",
                timestamp=time.time()
            )
            user_service.append_stats(username, stat1)
            
            # Check buffer
            assert len(user_service._stats_buffer[username]) == 1
            print("✅ Stat appended to buffer.")

            # Verify NOT yet in JSON (Check file directly to avoid auto-flush)
            with open(user_service._get_final_stats_path(username), "r") as f:
                data = json.load(f)
                assert data["total_play_time"] == 0
            print("✅ Stat NOT yet in JSON (correctly buffered).")

            print("\n--- 3. Verification of Flush ---")
            user_service.flush_stats()
            
            # Check buffer is empty
            assert len(user_service._stats_buffer[username]) == 0
            
            # Check JSON
            with open(user_service._get_final_stats_path(username), "r") as f:
                data = json.load(f)
                assert data["total_play_time"] == 120.0
                history = data["shuffle_state"]["history"]
                first_song = history[0]["filename"] if isinstance(history[0], dict) else history[0]
                assert first_song == "track1.mp3"
            print("✅ Data persisted to JSON after flush.")

            # Check SQL
            counts = user_service.get_play_counts(username)
            assert counts.get("track1.mp3") == 1
            print("✅ Data persisted to SQL after flush.")

            # Check Discord Logs
            # 1 for append_stats, 1 for flush_stats summary
            assert mock_queue.put.call_count >= 2
            all_msgs = [call[0][0] for call in mock_queue.put.call_args_list]
            flush_msg = next((m for m in reversed(all_msgs) if "Stats Flush Complete" in m), None)
            
            assert flush_msg is not None, "Flush summary message not found in logs"
            assert "Total Events:" in flush_msg
            assert "1" in flush_msg
            assert "track1.mp3" in flush_msg
            assert "buffer_test_user" in flush_msg
            print("✅ Discord logging verified (Exact data present).")

            print("\n--- 4. Testing Auto-Flush on Data Access ---")
            stat2 = StatsEntry(
                session_id="sess_abc",
                song_filename="track2.mp3",
                duration_played=50.0,
                total_length=200.0,
                event_type="complete",
                timestamp=time.time()
            )
            user_service.append_stats(username, stat2)
            assert len(user_service._stats_buffer[username]) == 1
            
            # This call should trigger a flush
            current_summary = user_service.get_stats_summary(username)
            assert current_summary["total_play_time"] == 170.0
            assert len(user_service._stats_buffer[username]) == 0
            print("✅ Auto-flush triggered by get_stats_summary.")

            print("\n✅ BUFFERING TESTS PASSED")

        except Exception as e:
            print(f"\n❌ TEST FAILED: {e}")
            import traceback
            traceback.print_exc()
            sys.exit(1)
        finally:
            print("Cleaning up...")
            shutil.rmtree(TEST_DIR)

if __name__ == "__main__":
    test_stats_buffering_and_flushing()
