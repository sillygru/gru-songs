import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    MUSIC_DIR = os.getenv("MUSIC_DIR", "/home/sillygru/Documents/music/Songs")
    LYRICS_DIR = os.getenv("LYRICS_DIR", "/home/sillygru/Documents/music/Lyrics")

settings = Settings()
