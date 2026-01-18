import os
from settings import settings

class MusicService:
    def list_songs(self):
        # Server no longer manages song list logically, it only syncs DBs
        return []

    def verify_song(self, file_path: str) -> bool:
        # No longer used as server doesn't handle audio files
        return False

    def get_embedded_lyrics(self, filename: str):
        return None

    def get_cover_data(self, filename: str):
        return None, None

    def get_song_duration(self, filename: str) -> float:
        # In offline-first mode, the server doesn't have the audio files
        # Duration should be provided by the client in stats or synced via DB
        return 0.0

music_service = MusicService()