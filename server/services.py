import os
from mutagen import File as MutagenFile
from settings import settings

class MusicService:
    def list_songs(self):
        songs = []
        if not os.path.exists(settings.MUSIC_DIR):
            return {"error": f"Directory not found: {settings.MUSIC_DIR}"}

        # Directories to scan
        scan_dirs = [settings.MUSIC_DIR, settings.DOWNLOADED_DIR]
        
        for base_dir in scan_dirs:
            if not os.path.exists(base_dir):
                continue
                
            for file_name in os.listdir(base_dir):
                if file_name.lower().endswith((".m4a", ".mp3", ".flac", ".wav", ".alac")):
                    path = os.path.join(base_dir, file_name)
                    
                    display_name = file_name.rsplit('.', 1)[0]
                    
                    # Check for custom title from uploads.json (user set)
                    from user_service import user_service
                    custom_title = user_service.get_custom_title(file_name)
                    
                    # Use easy=True for unified title/artist access across formats
                    try:
                        audio = MutagenFile(path, easy=True)
                    except Exception:
                        audio = None
                    
                    title = custom_title if custom_title else display_name
                    artist = "Unknown"
                    album = "Unknown Album"

                    if audio:
                        # Only use metadata title if there's no custom title
                        if not custom_title:
                            title = audio.get("title", [display_name])[0]
                        artist = audio.get("artist", ["Unknown"])[0]
                        album = audio.get("album", ["Unknown Album"])[0]

                    lrc_file = f"{display_name}.lrc"
                    has_lrc = os.path.exists(os.path.join(settings.LYRICS_DIR, lrc_file))
                    
                    lyrics_url = f"/lyrics/{lrc_file}" if has_lrc else None
                    
                    # Fallback to embedded lyrics if no .lrc file exists
                    if not lyrics_url:
                        # Re-open without easy=True to access specific tags
                        try:
                            raw_audio = MutagenFile(path)
                            if raw_audio:
                                # Check for common embedded lyrics tags
                                if "\xa9lyr" in raw_audio or any(k.startswith("USLT") for k in raw_audio.keys()):
                                    lyrics_url = f"/lyrics-embedded/{file_name}"
                        except Exception:
                            pass
                    
                    songs.append({
                        "title": str(title),
                        "artist": str(artist),
                        "album": str(album),
                        "filename": file_name,
                        "url": f"/stream/{file_name}",
                        "lyrics_url": lyrics_url,
                        "cover_url": f"/cover/{file_name}",
                        "duration": self.get_song_duration(file_name)
                    })
        
        # Deduplicate if same filename exists in multiple dirs (prefer original MUSIC_DIR)
        seen = set()
        unique_songs = []
        for s in songs:
            if s["filename"] not in seen:
                unique_songs.append(s)
                seen.add(s["filename"])
        
        return sorted(unique_songs, key=lambda x: x['title'])

    def verify_song(self, file_path: str) -> bool:
        try:
            audio = MutagenFile(file_path)
            return audio is not None
        except Exception:
            return False

    def get_embedded_lyrics(self, filename: str):
        # Check both directories
        path = os.path.join(settings.MUSIC_DIR, filename)
        if not os.path.exists(path):
            path = os.path.join(settings.DOWNLOADED_DIR, filename)
            
        if not os.path.exists(path):
            return None
        
        try:
            audio = MutagenFile(path)
        except Exception:
            return None

        if not audio:
            return None

        lyrics = None
        if "\xa9lyr" in audio:
            lyrics = audio["\xa9lyr"][0]
        else:
            for key in audio.keys():
                if key.startswith("USLT"):
                    lyrics = audio[key].text
                    if isinstance(lyrics, list):
                        lyrics = lyrics[0]
                    break
        return lyrics

    def get_cover_data(self, filename: str):
        # Check both directories
        path = os.path.join(settings.MUSIC_DIR, filename)
        if not os.path.exists(path):
            path = os.path.join(settings.DOWNLOADED_DIR, filename)
            
        if not os.path.exists(path):
            return None, None
        
        try:
            audio = MutagenFile(path)
        except Exception:
            return None, None

        if not audio:
            return None, None

        # Handle MP3 (ID3)
        for key in audio.keys():
            if key.startswith("APIC"):
                return audio[key].data, audio[key].mime
        
        # Handle M4A (MP4)
        if "covr" in audio:
            return audio["covr"][0], "image/jpeg"

        # Handle FLAC
        if hasattr(audio, 'pictures') and audio.pictures:
            return audio.pictures[0].data, audio.pictures[0].mime

        return None, None

    def get_song_duration(self, filename: str) -> float:
        # Check both directories
        path = os.path.join(settings.MUSIC_DIR, filename)
        if not os.path.exists(path):
            path = os.path.join(settings.DOWNLOADED_DIR, filename)
            
        if not os.path.exists(path):
            return 0.0
        
        try:
            audio = MutagenFile(path)
            if audio and audio.info and audio.info.length:
                return float(audio.info.length)
        except Exception:
            pass

        # Fallback to ffprobe if mutagen fails
        try:
            import subprocess
            cmd = [
                "ffprobe",
                "-v", "error",
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                path
            ]
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode == 0:
                return float(result.stdout.strip())
        except Exception:
            pass

        return 0.0

music_service = MusicService()
