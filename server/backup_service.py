import os
import shutil
import asyncio
import datetime
import time
import json
import hashlib
from settings import settings
from multiprocessing import Queue

class BackupService:
    def __init__(self):
        self.discord_queue = None
        self._is_backing_up = False
        self.state_file = os.path.join(os.path.dirname(__file__), "backup_state.json")
        self.history_file = os.path.join(os.path.dirname(__file__), "server_history.log")
        state_data = self._load_state()
        self.last_run_timestamp = state_data.get("last_run_timestamp", time.time())
        self.last_backup_hash = state_data.get("last_backup_hash", "")
        # Next run is 6 hours after the last successful check (even if skipped)
        self.next_run_timestamp = self.last_run_timestamp + (6 * 60 * 60)

    def set_discord_queue(self, queue: Queue):
        self.discord_queue = queue

    def _log(self, message: str):
        print(message)
        if self.discord_queue:
            self.discord_queue.put(message)

    def log_event(self, event_type: str, details: str = ""):
        try:
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            log_line = f"[{timestamp}] {event_type}"
            if details:
                log_line += f": {details}"
            
            with open(self.history_file, 'a') as f:
                f.write(log_line + "\n")
        except Exception as e:
            print(f"Failed to log event: {e}")

    def _load_state(self) -> dict:
        try:
            if os.path.exists(self.state_file):
                with open(self.state_file, 'r') as f:
                    return json.load(f)
        except Exception:
            pass
        return {}

    def _save_state(self):
        try:
            with open(self.state_file, 'w') as f:
                json.dump({
                    "last_run_timestamp": self.last_run_timestamp,
                    "last_backup_hash": self.last_backup_hash
                }, f, indent=4)
        except Exception as e:
            print(f"Failed to save backup state: {e}")

    def _get_users_dir_hash(self):
        """Calculates a deterministic hash of the users directory based on filenames, sizes, and mtimes."""
        hasher = hashlib.md5()
        
        # Sort files to ensure deterministic order
        try:
            files = []
            for root, dirs, filenames in os.walk(settings.USERS_DIR):
                for filename in filenames:
                    if filename.startswith('.'): continue
                    full_path = os.path.join(root, filename)
                    rel_path = os.path.relpath(full_path, settings.USERS_DIR)
                    files.append(rel_path)
            
            files.sort()
            
            for rel_path in files:
                full_path = os.path.join(settings.USERS_DIR, rel_path)
                stat = os.stat(full_path)
                # Include path, size and mtime in the hash. 
                # This is faster than reading all file contents and usually sufficient.
                # If we want to be 100% sure for SQLite, we could read the first few KB or whole file.
                # Given the 6h interval, reading contents of a few MBs of DBs is also fine.
                hasher.update(rel_path.encode())
                hasher.update(str(stat.st_size).encode())
                hasher.update(str(stat.st_mtime).encode())
                
                # For small JSON files, let's include content hash for extra safety
                if rel_path.endswith('.json'):
                    try:
                        with open(full_path, 'rb') as f:
                            hasher.update(f.read())
                    except: pass
                    
        except Exception as e:
            print(f"Hash calculation error: {e}")
            return str(time.time()) # Force backup on error
            
        return hasher.hexdigest()

    async def trigger_backup(self, reset_timer: bool = False):
        if self._is_backing_up:
            return False, "Backup already in progress"
            
        success = await self.perform_backup()
        
        if success and reset_timer:
            self.last_run_timestamp = time.time()
            self.next_run_timestamp = self.last_run_timestamp + (6 * 60 * 60)
            self._save_state()
            self._log(f"⏰ Timer reset. Next backup at: {datetime.datetime.fromtimestamp(self.next_run_timestamp).strftime('%H:%M')}")
            
        return success, "Backup completed"

    async def perform_backup(self):
        if self._is_backing_up:
            return False
            
        self._is_backing_up = True
        try:
            result = await asyncio.to_thread(self._perform_backup_sync)
            if result != "failed":
                self.last_run_timestamp = time.time()
                self._save_state()
                return True
            return False
        finally:
            self._is_backing_up = False

    def _perform_backup_sync(self):
        start_time = time.time()
        
        current_hash = self._get_users_dir_hash()
        if current_hash == self.last_backup_hash:
            self._log("⏭️ Backup skipped: No changes detected in user data.")
            self.log_event("BACKUP_SKIPPED", "No changes")
            return "skipped"

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
            
            # Zip and send to discord
            try:
                zip_base_name = os.path.join(settings.BACKUPS_DIR, folder_name)
                # This creates {zip_base_name}.zip
                zip_path = shutil.make_archive(zip_base_name, 'zip', settings.USERS_DIR)
                
                if self.discord_queue:
                    self.discord_queue.put({
                        "type": "file",
                        "path": zip_path,
                        "filename": f"{folder_name}.zip",
                        "content": f"📦 **Backup {next_num}** ({folder_name})"
                    })
            except Exception as e:
                self._log(f"⚠️ Failed to create/send zip backup: {e}")

            elapsed = time.time() - start_time
            self.last_backup_hash = current_hash
            msg = f"✅ Backup {next_num} completed in {elapsed:.2f}s: {folder_name}"
            self._log(msg)
            self.log_event("BACKUP", folder_name)
            return "success"
            
        except Exception as e:
            self._log(f"❌ Backup failed: {str(e)}")
            return "failed"

    async def start_scheduler(self):
        self._log(f"⏳ Backup scheduler started. Next run: {datetime.datetime.fromtimestamp(self.next_run_timestamp).strftime('%Y-%m-%d %H:%M:%S')}")
        while True:
            now = time.time()
            if now >= self.next_run_timestamp:
                success = await self.perform_backup()
                if success:
                    # Schedule next
                    self.next_run_timestamp = self.last_run_timestamp + (6 * 60 * 60)
                    self._log(f"⏰ Next backup scheduled for: {datetime.datetime.fromtimestamp(self.next_run_timestamp).strftime('%H:%M')}")
                else:
                    # Retry in 1 hour if failed? Or keep trying?
                    # Let's retry in 1 hour
                    self.next_run_timestamp = time.time() + (60 * 60)
                    self._log("⚠️ Backup failed, retrying in 1 hour.")
            
            # Check every minute
            await asyncio.sleep(60)

backup_service = BackupService()
