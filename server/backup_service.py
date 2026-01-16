import os
import shutil
import asyncio
import datetime
import time
import json
from settings import settings
from multiprocessing import Queue

class BackupService:
    def __init__(self):
        self.discord_queue = None
        self._is_backing_up = False
        self.state_file = os.path.join(os.path.dirname(__file__), "backup_state.json")
        self.next_run_timestamp = self._load_state()

    def set_discord_queue(self, queue: Queue):
        self.discord_queue = queue

    def _log(self, message: str):
        print(message)
        if self.discord_queue:
            self.discord_queue.put(message)

    def _load_state(self) -> float:
        try:
            if os.path.exists(self.state_file):
                with open(self.state_file, 'r') as f:
                    data = json.load(f)
                    return data.get("next_run_timestamp", 0)
        except Exception:
            pass
        # Default to now + 6 hours if no state
        return time.time() + (6 * 60 * 60)

    def _save_state(self):
        try:
            with open(self.state_file, 'w') as f:
                json.dump({"next_run_timestamp": self.next_run_timestamp}, f)
        except Exception as e:
            print(f"Failed to save backup state: {e}")

    async def trigger_backup(self, reset_timer: bool = False):
        if self._is_backing_up:
            return False, "Backup already in progress"
            
        success = await self.perform_backup()
        
        if success and reset_timer:
            self.next_run_timestamp = time.time() + (6 * 60 * 60)
            self._save_state()
            self._log(f"⏰ Timer reset. Next backup at: {datetime.datetime.fromtimestamp(self.next_run_timestamp).strftime('%H:%M')}")
            
        return success, "Backup completed"

    async def perform_backup(self):
        if self._is_backing_up:
            return False
            
        self._is_backing_up = True
        try:
            return await asyncio.to_thread(self._perform_backup_sync)
        finally:
            self._is_backing_up = False

    def _perform_backup_sync(self):
        start_time = time.time()
        
        try:
            # Calculate name
            now = datetime.datetime.now()
            # Format: 03_26_01_16_18_44
            # [number]_%y_%m_%d_%H_%M
            timestamp = now.strftime("%y_%m_%d_%H_%M")
            
            # Correct path construction
            real_backup_root = os.path.join(settings.BACKUPS_DIR, "users")
            if not os.path.exists(real_backup_root):
                os.makedirs(real_backup_root)
                
            # Scan for max num
            max_num = 0
            try:
                backups = os.listdir(real_backup_root)
                for name in backups:
                    # ignore .DS_Store etc
                    if name.startswith('.'): continue
                    
                    parts = name.split('_', 1)
                    if len(parts) > 1 and parts[0].isdigit():
                        num_found = int(parts[0])
                        if num_found > max_num:
                            max_num = num_found
            except Exception:
                pass
            
            next_num = max_num + 1
            folder_name = f"{next_num:02d}_{timestamp}"
            dest_path = os.path.join(real_backup_root, folder_name)

            shutil.copytree(settings.USERS_DIR, dest_path)
            
            elapsed = time.time() - start_time
            self._log(f"✅ Backup {next_num} completed in {elapsed:.2f}s: {folder_name}")
            return True
            
        except Exception as e:
            self._log(f"❌ Backup failed: {str(e)}")
            return False

    async def start_scheduler(self):
        self._log(f"⏳ Backup scheduler started. Next run: {datetime.datetime.fromtimestamp(self.next_run_timestamp).strftime('%Y-%m-%d %H:%M:%S')}")
        while True:
            now = time.time()
            if now >= self.next_run_timestamp:
                success = await self.perform_backup()
                if success:
                    # Schedule next
                    self.next_run_timestamp = time.time() + (6 * 60 * 60)
                    self._save_state()
                    self._log(f"⏰ Next backup scheduled for: {datetime.datetime.fromtimestamp(self.next_run_timestamp).strftime('%H:%M')}")
                else:
                    # Retry in 1 hour if failed? Or keep trying?
                    # Let's retry in 1 hour
                    self.next_run_timestamp = time.time() + (60 * 60)
                    self._log("⚠️ Backup failed, retrying in 1 hour.")
            
            # Check every minute
            await asyncio.sleep(60)

backup_service = BackupService()
