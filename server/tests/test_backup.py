import asyncio
import os
import shutil
import sys
import tempfile
from multiprocessing import Queue

# Setup env BEFORE importing settings
os.environ["GRUSONGS_TESTING"] = "true"
test_dir = tempfile.mkdtemp()
os.environ["MUSIC_DIR"] = os.path.join(test_dir, "music")
os.environ["USERS_DIR"] = os.path.join(test_dir, "users")
os.environ["BACKUPS_DIR"] = os.path.join(test_dir, "backups")

# Add server directory to path so we can import modules
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backup_service import backup_service
from settings import settings

def test_backup():
    async def run_test():
        print("🚀 Starting Backup Test")
        
        # Mock queue
        mock_queue = Queue()
        backup_service.set_discord_queue(mock_queue)
        
        # Ensure users dir has something
        users_dir = settings.USERS_DIR
        if not os.path.exists(users_dir):
            os.makedirs(users_dir, exist_ok=True)
            
        with open(os.path.join(users_dir, "test_file.txt"), "w") as f:
            f.write("test content")

        # Perform backup
        print("⏳ Running backup...")
        success = await backup_service.perform_backup()
        
        if not success:
            print("❌ Backup failed")
            return False

        # Check queue for message
        try:
            msg = mock_queue.get_nowait()
            print(f"📨 Discord Message received: {msg}")
        except:
            print("⚠️ No discord message received")

        # Verify directory structure
        backup_root = os.path.join(settings.BACKUPS_DIR, "users")
        if not os.path.exists(backup_root):
            print("❌ Backup root directory not found")
            return False

        backups = sorted(os.listdir(backup_root))
        if not backups:
            print("❌ No backup directory found")
            return False
            
        latest_backup = backups[-1]
        print(f"✅ Found backup directory: {latest_backup}")
        
        # Verify content
        latest_path = os.path.join(backup_root, latest_backup)
        if os.path.exists(os.path.join(latest_path, "test_file.txt")) or \
           any(f.endswith(".db") for f in os.listdir(latest_path)):
            print("✅ Content verified")
        else:
            print("❌ Content verification failed (files missing)")
            return False

        print("✅ Test Passed")
        return True

    assert asyncio.run(run_test())

if __name__ == "__main__":
    test_backup()
