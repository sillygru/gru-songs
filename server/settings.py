import os
from dotenv import load_dotenv
from config_manager import config_manager

# Skip loading .env if we're in testing mode to avoid server-specific paths
if os.getenv("GRUSONGS_TESTING") != "true":
    load_dotenv()

class Settings:
    VERSION: str = "7.2.0"

    @property
    def BASE_DIR(self) -> str:
        return os.path.dirname(os.path.abspath(__file__))

    @property
    def MUSIC_DIR(self) -> str:
        return os.getenv("MUSIC_DIR", "songs")

    @property
    def LYRICS_DIR(self) -> str:
        return os.getenv("LYRICS_DIR", os.path.join(self.MUSIC_DIR, "lyrics"))

    @property
    def DOWNLOADED_DIR(self) -> str:
        return os.path.join(self.MUSIC_DIR, "downloaded")

    @property
    def USERS_DIR(self) -> str:
        return os.getenv("USERS_DIR", os.path.join(os.path.dirname(__file__), "users"))

    @property
    def BACKUPS_DIR(self) -> str:
        return os.getenv("BACKUPS_DIR", os.path.join(os.path.dirname(__file__), "backups"))

    @property
    def DISCORD_TOKEN(self) -> str:
        return os.getenv("DISCORD_TOKEN")

    @property
    def DISCORD_CHANNEL_ID(self) -> str:
        return os.getenv("DISCORD_CHANNEL_ID")

    @property
    def USE_DISCORD_BOT(self) -> bool:
        return config_manager.get("use_discord_bot", False)

    @property
    def LOG_TO_DISCORD(self) -> bool:
        return config_manager.get("log_to_discord", False)

    @property
    def BACKUP_ENABLED(self) -> bool:
        return config_manager.get("backup_enabled", False)

    @property
    def BACKUP_INTERVAL_HOURS(self) -> int:
        return config_manager.get("backup_interval_hours", 6)

    @property
    def SEND_BACKUPS_TO_DISCORD(self) -> bool:
        return config_manager.get("send_backups_to_discord", False)

    @property
    def SKIP_IDENTICAL_BACKUPS(self) -> bool:
        return config_manager.get("skip_identical_backups", True)

    def __init__(self):
        # We'll create directories lazily or when specifically requested if needed,
        # but let's keep a method to ensure they exist.
        pass

    def ensure_dirs(self):
        for d in [self.MUSIC_DIR, self.LYRICS_DIR, self.DOWNLOADED_DIR, self.USERS_DIR, self.BACKUPS_DIR]:
            try:
                if not os.path.exists(d):
                    os.makedirs(d, exist_ok=True)
            except Exception as e:
                if os.getenv("GRUSONGS_TESTING") != "true":
                    print(f"Warning: Could not create directory {d}: {e}")

    def validate_discord(self):
        if not self.USE_DISCORD_BOT:
            return False, "Discord bot disabled in config."
        
        token = self.DISCORD_TOKEN
        channel_id = self.DISCORD_CHANNEL_ID
        
        if not token or token == "guess":
            return False, "DISCORD_TOKEN is missing or invalid."
        if not channel_id or channel_id == "guess":
            return False, "DISCORD_CHANNEL_ID is missing or invalid."
            
        return True, "Discord settings valid."

settings = Settings()
# Initial ensure
settings.ensure_dirs()
