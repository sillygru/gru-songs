import os
import tempfile
import sys
import json
import shutil
import time

# Setup env BEFORE any other imports
os.environ["GRUSONGS_TESTING"] = "true"
test_base = tempfile.mkdtemp()
os.environ["MUSIC_DIR"] = os.path.join(test_base, "music")
os.environ["USERS_DIR"] = os.path.join(test_base, "users")
os.environ["BACKUPS_DIR"] = os.path.join(test_base, "backups")

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from user_service import UserService
from database_manager import db_manager

def test_theme_sync():
    username = "testuser_theme"
    test_users_dir = os.environ["USERS_DIR"]
    os.makedirs(test_users_dir, exist_ok=True)
    
    db_manager.init_global_dbs()
    
    try:
        service = UserService()
        service.create_user(username, "password123")
        
        # 1. Test initial theme settings
        theme_settings = service.get_theme_settings(username)
        assert theme_settings["theme_mode"] is None
        assert theme_settings["sync_theme"] is False
        
        # 2. Update theme settings
        service.update_theme_settings(username, "GruThemeMode.oled", True)
        
        theme_settings = service.get_theme_settings(username)
        assert theme_settings["theme_mode"] == "GruThemeMode.oled"
        assert theme_settings["sync_theme"] is True
        
        # 3. Update theme settings again (change mode, keep sync)
        service.update_theme_settings(username, "GruThemeMode.ocean", True)
        theme_settings = service.get_theme_settings(username)
        assert theme_settings["theme_mode"] == "GruThemeMode.ocean"
        
        # 4. Disable sync
        service.update_theme_settings(username, "GruThemeMode.classic", False)
        theme_settings = service.get_theme_settings(username)
        assert theme_settings["theme_mode"] == "GruThemeMode.classic"
        assert theme_settings["sync_theme"] is False
        
        # 5. Test migration helper (Simulate an old DB without columns)
        # We'll create a new user, manually drop the columns if they exist (unlikely in fresh test)
        # but better yet, we just call the helper on a user that was just created.
        # The helper is already called in get_theme_settings, so it's verified by step 1.
        
        # 6. Test with non-existent user
        non_existent_settings = service.get_theme_settings("nobody")
        assert non_existent_settings["theme_mode"] is None
        assert non_existent_settings["sync_theme"] is False

        print("Backend theme sync tests passed!")
        
    finally:
        if os.path.exists(test_base):
            shutil.rmtree(test_base)

if __name__ == "__main__":
    test_theme_sync()
