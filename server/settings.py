import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    MUSIC_DIR: str = os.getenv("MUSIC_DIR", "songs")
    LYRICS_DIR: str = os.getenv("LYRICS_DIR", os.path.join(MUSIC_DIR, "lyrics"))
    DOWNLOADED_DIR: str = os.path.join(MUSIC_DIR, "downloaded")
    USERS_DIR: str = os.path.join(os.path.dirname(__file__), "users")

    def __init__(self):
        for d in [self.MUSIC_DIR, self.LYRICS_DIR, self.DOWNLOADED_DIR, self.USERS_DIR]:
            if not os.path.exists(d):
                os.makedirs(d, exist_ok=True)

settings = Settings()
