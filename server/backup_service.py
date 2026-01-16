import os
import shutil
import asyncio
import datetime
import time
from settings import settings
from multiprocessing import Queue

class BackupService:
    def __init__(self):
        self.discord_queue = None

    def set_discord_queue(self, queue: Queue):
        self.discord_queue = queue

    def _log(self, message: str):
        print(message)
        if self.discord_queue:
            self.discord_queue.put(message)

    async def perform_backup(self):
        return await asyncio.to_thread(self._perform_backup_sync)

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
        # 6 hours in seconds
        INTERVAL = 6 * 60 * 60
        while True:
            await asyncio.sleep(INTERVAL)
            await self.perform_backup()

backup_service = BackupService()
