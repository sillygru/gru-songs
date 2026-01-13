import os
import json
import shutil
from user_service import UserService
from models import StatsEntry
import time

def test_shuffle_persistence():
    # Setup
    username = "testuser_shuffle"
    users_dir = "users_test"
    if not os.path.exists(users_dir):
        os.makedirs(users_dir)
    
    # Mock settings to use test dir
    from settings import settings
    original_users_dir = settings.USERS_DIR
    settings.USERS_DIR = users_dir
    
    try:
        service = UserService()
        # Create user
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
        assert summary["shuffle_state"]["history"] == ["song1.mp3", "song2.mp3"]
        
        # 3. Test appending stats updates history
        stats = StatsEntry(
            session_id="session1",
            song_filename="song3.mp3",
            duration_played=120.0,
            event_type="complete",
            timestamp=time.time()
        )
        service.append_stats(username, stats)
        
        summary = service.get_stats_summary(username)
        # song3 should be at the front of history
        assert summary["shuffle_state"]["history"][0] == "song3.mp3"
        assert "song1.mp3" in summary["shuffle_state"]["history"]
        
        # 4. Test history limit
        service.update_shuffle_state(username, {"config": {"history_limit": 2}})
        stats = StatsEntry(
            session_id="session1",
            song_filename="song4.mp3",
            duration_played=120.0,
            event_type="complete",
            timestamp=time.time()
        )
        service.append_stats(username, stats)
        summary = service.get_stats_summary(username)
        assert len(summary["shuffle_state"]["history"]) <= 2
        assert summary["shuffle_state"]["history"][0] == "song4.mp3"

        print("Backend shuffle persistence tests passed!")
        
    finally:
        # Cleanup
        if os.path.exists(users_dir):
            shutil.rmtree(users_dir)
        settings.USERS_DIR = original_users_dir

if __name__ == "__main__":
    test_shuffle_persistence()
