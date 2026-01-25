import pytest
import os
import shutil
import time
from sqlalchemy import select
from sqlalchemy.orm import Session
from settings import settings
from database_manager import db_manager
from user_service import user_service
from db_models import Playlist, PlaylistSong

@pytest.fixture(autouse=True)
def setup_teardown():
    # Setup
    if os.path.exists(settings.USERS_DIR):
        shutil.rmtree(settings.USERS_DIR)
    os.makedirs(settings.USERS_DIR)
    db_manager.init_global_dbs()
    yield
    # Teardown
    if os.path.exists(settings.USERS_DIR):
        shutil.rmtree(settings.USERS_DIR)

def test_playlist_crud():
    username = "testuser"
    user_service.create_user(username, "password")
    
    # Create playlist
    pl_id = "pl1"
    pl_name = "My Playlist"
    now = time.time()
    
    playlists = [
        {
            "id": pl_id,
            "name": pl_name,
            "created_at": now,
            "updated_at": now,
            "songs": [
                {"song_filename": "song1.mp3", "added_at": now}
            ]
        }
    ]
    
    # Sync (Create)
    synced = user_service.sync_playlists(username, playlists)
    assert len(synced) == 1
    assert synced[0]["name"] == pl_name
    assert len(synced[0]["songs"]) == 1
    
    # Add song via sync
    playlists[0]["songs"].append({"song_filename": "song2.mp3", "added_at": now + 10})
    playlists[0]["updated_at"] = now + 10
    
    synced = user_service.sync_playlists(username, playlists)
    assert len(synced[0]["songs"]) == 2
    
    # Delete playlist
    user_service.delete_playlist(username, pl_id)
    synced = user_service.get_playlists(username)
    assert len(synced) == 0

def test_playlist_rename_file():
    username = "testuser"
    user_service.create_user(username, "password")
    
    pl_id = "pl1"
    now = time.time()
    playlists = [
        {
            "id": pl_id,
            "name": "Renamable",
            "created_at": now,
            "updated_at": now,
            "songs": [
                {"song_filename": "old.mp3", "added_at": now}
            ]
        }
    ]
    user_service.sync_playlists(username, playlists)
    
    # Rename file
    user_service.rename_file(username, "old.mp3", "new.mp3", device_count=0)
    
    # Check playlist
    synced = user_service.get_playlists(username)
    assert len(synced[0]["songs"]) == 1
    assert synced[0]["songs"][0]["song_filename"] == "new.mp3"

def test_playlist_merge_on_rename():
    username = "testuser"
    user_service.create_user(username, "password")
    
    pl_id = "pl1"
    now = time.time()
    playlists = [
        {
            "id": pl_id,
            "name": "Merge Test",
            "created_at": now,
            "updated_at": now,
            "songs": [
                {"song_filename": "a.mp3", "added_at": now},
                {"song_filename": "b.mp3", "added_at": now + 1}
            ]
        }
    ]
    user_service.sync_playlists(username, playlists)
    
    # Rename a.mp3 to b.mp3 (should merge/delete one)
    user_service.rename_file(username, "a.mp3", "b.mp3", device_count=0)
    
    synced = user_service.get_playlists(username)
    assert len(synced[0]["songs"]) == 1
    assert synced[0]["songs"][0]["song_filename"] == "b.mp3"
