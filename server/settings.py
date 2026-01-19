import os
from dotenv import load_dotenv

# Skip loading .env if we're in testing mode to avoid server-specific paths
if os.getenv("GRUSONGS_TESTING") != "true":
    load_dotenv()

class Settings:
    VERSION: str = "6.2.0"

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

settings = Settings()
# Initial ensure
settings.ensure_dirs()
