import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    MUSIC_DIR: str = os.getenv("MUSIC_DIR", os.path.expanduser("~/Music"))
    LYRICS_DIR: str = os.getenv("LYRICS_DIR", os.path.join(MUSIC_DIR, "lyrics"))
    USERS_DIR: str = os.path.join(os.path.dirname(__file__), "users")

settings = Settings()
