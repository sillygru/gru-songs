from fastapi import FastAPI, HTTPException, Header, UploadFile, File, Form
from fastapi.responses import Response, FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from typing import Dict, Any, List, Optional
import os
import subprocess
import shutil
import tempfile
import asyncio
from contextlib import asynccontextmanager

from settings import settings
from services import music_service
from user_service import user_service
from models import UserCreate, UserLogin, UserUpdate, StatsEntry, UserProfileUpdate, PlaylistCreate, PlaylistAddSong, FavoriteRequest

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup logic
    asyncio.create_task(periodic_flush())
    yield
    # Shutdown logic
    user_service.flush_stats()

app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Custom stream route to handle multiple directories
@app.get("/stream/{filename}")
async def stream_song(filename: str):
    path = os.path.join(settings.MUSIC_DIR, filename)
    if not os.path.exists(path):
        path = os.path.join(settings.DOWNLOADED_DIR, filename)
    
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="Song not found")
    
    return FileResponse(path)

app.mount("/lyrics", StaticFiles(directory=settings.LYRICS_DIR), name="lyrics")

# --- Background Task for Stats Flushing ---

async def periodic_flush():
    while True:
        await asyncio.sleep(300) # 5 minutes
        user_service.flush_stats()

# --- Auth Routes ---

@app.post("/auth/signup")
def signup(user: UserCreate):
    success, message = user_service.create_user(user.username, user.password)
    if not success:
        raise HTTPException(status_code=400, detail=message)
    return {"message": message}

@app.post("/auth/login")
def login(user: UserLogin):
    if user_service.authenticate_user(user.username, user.password):
        return {"message": "Login successful", "username": user.username}
    raise HTTPException(status_code=401, detail="Invalid credentials")

@app.post("/auth/update-password")
def update_password(data: UserUpdate, x_username: str = Header(None)):
    if not x_username:
         raise HTTPException(status_code=401, detail="User not authenticated")
    
    success, message = user_service.update_password(x_username, data.old_password, data.new_password)
    if not success:
        raise HTTPException(status_code=400, detail=message)
    return {"message": message}

@app.post("/auth/update-username")
def update_username(data: UserProfileUpdate, x_username: str = Header(None)):
    if not x_username:
         raise HTTPException(status_code=401, detail="User not authenticated")
    
    if not data.new_username:
        raise HTTPException(status_code=400, detail="New username required")

    success, message = user_service.update_username(x_username, data.new_username)
    if not success:
        raise HTTPException(status_code=400, detail=message)
    return {"username": data.new_username, "message": message}


# --- Stats Routes ---

@app.get("/stats/summary")
@app.get("/user/shuffle")
async def get_stats_summary(x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="Missing username header")
    return user_service.get_stats_summary(x_username)

@app.post("/stats/shuffle-state")
@app.post("/user/shuffle")
async def update_shuffle_state(state: Dict[str, Any], x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="Missing username header")
    return user_service.update_shuffle_state(x_username, state)

@app.post("/stats/track")
def track_stats(stats: StatsEntry, x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")
    
    user_service.append_stats(x_username, stats)
    return {"status": "ok"}


# --- User Data Routes (Favorites & Playlists) ---

@app.get("/user/favorites")
def get_favorites(x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")
    return user_service.get_favorites(x_username)

@app.post("/user/favorites")
def add_favorite(req: FavoriteRequest, x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")
    user_service.add_favorite(x_username, req.song_filename, req.session_id)
    return {"status": "added"}

@app.delete("/user/favorites/{filename}")
def remove_favorite(filename: str, x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")
    user_service.remove_favorite(x_username, filename)
    return {"status": "removed"}

# --- Suggest Less Routes ---

@app.get("/user/suggest-less")
def get_suggest_less(x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")
    return user_service.get_suggest_less(x_username)

@app.post("/user/suggest-less")
def add_suggest_less(req: PlaylistAddSong, x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")
    user_service.add_suggest_less(x_username, req.song_filename)
    return {"status": "added"}

@app.delete("/user/suggest-less/{filename}")
def remove_suggest_less(filename: str, x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")
    user_service.remove_suggest_less(x_username, filename)
    return {"status": "removed"}

# --- Playlist Routes ---

@app.get("/user/playlists")
def get_playlists(x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")
    return user_service.get_playlists(x_username)

@app.post("/user/playlists")
def create_playlist(req: PlaylistCreate, x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")
    playlist = user_service.create_playlist(x_username, req.name)
    if not playlist:
         raise HTTPException(status_code=400, detail="Could not create playlist")
    return playlist

@app.delete("/user/playlists/{playlist_id}")
def delete_playlist(playlist_id: str, x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")
    user_service.delete_playlist(x_username, playlist_id)
    return {"status": "deleted"}

@app.post("/user/playlists/{playlist_id}/songs")
def add_song_to_playlist(playlist_id: str, req: PlaylistAddSong, x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")
    user_service.add_song_to_playlist(x_username, playlist_id, req.song_filename)
    return {"status": "added"}

@app.delete("/user/playlists/{playlist_id}/songs/{filename}")
def remove_song_from_playlist(playlist_id: str, filename: str, x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")
    user_service.remove_song_from_playlist(x_username, playlist_id, filename)
    return {"status": "removed"}


# --- Music Routes ---

@app.get("/list-songs")
def list_songs(x_username: str = Header(None)):
    result = music_service.list_songs()
    if isinstance(result, dict) and "error" in result:
        return result
    
    if x_username:
        counts = user_service.get_play_counts(x_username)
        for song in result:
            song["play_count"] = counts.get(song["filename"], 0)
            
    return result

@app.get("/sync-check")
def sync_check(x_username: str = Header(None)):
    return user_service.get_sync_hashes(x_username)

@app.get("/lyrics-embedded/{filename}")
def get_embedded_lyrics(filename: str):
    lyrics = music_service.get_embedded_lyrics(filename)
    if not lyrics:
        raise HTTPException(status_code=404, detail="No embedded lyrics found")
    
    return Response(
        content=str(lyrics), 
        media_type="text/plain",
        headers={"Cache-Control": "public, max-age=31536000, immutable"}
    )

@app.get("/cover/{filename}")
def get_cover(filename: str):
    data, mime = music_service.get_cover_data(filename)
    if not data:
        raise HTTPException(status_code=404, detail="No cover found in metadata")
    
    return Response(
        content=data, 
        media_type=mime,
        headers={"Cache-Control": "public, max-age=31536000, immutable"}
    )

@app.post("/music/upload")
async def upload_song(
    file: UploadFile = File(...), 
    filename: str = Form(None),
    x_username: str = Header(None)
):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")

    # Use provided filename or original filename
    final_filename = filename if filename else file.filename
    # Ensure it has a valid extension if not provided
    if not any(final_filename.lower().endswith(ext) for ext in [".mp3", ".m4a", ".flac", ".wav", ".alac"]):
        ext = os.path.splitext(file.filename)[1]
        if not ext:
            ext = ".mp3" # Fallback
        final_filename += ext

    # Save to RAM (initially)
    content = await file.read()

    # Create a temp file for verification (Mutagen often needs a path)
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(content)
        tmp_path = tmp.name

    try:
        # Verify
        if not music_service.verify_song(tmp_path):
            os.remove(tmp_path)
            raise HTTPException(status_code=400, detail="Invalid audio file")

        # Save to downloaded dir
        dest_path = os.path.join(settings.DOWNLOADED_DIR, final_filename)
        # Move the temp file to destination
        shutil.move(tmp_path, dest_path)
        
        # Record uploader with title
        display_title = final_filename.rsplit('.', 1)[0]
        user_service.record_upload(
            x_username, 
            final_filename, 
            display_title, 
            source="file", 
            original_filename=file.filename
        )
        
        return {"message": "Upload successful", "filename": final_filename}
    except Exception as e:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/music/yt-dlp")
async def ytdlp_download(
    url: str = Form(...),
    filename: str = Form(None),
    x_username: str = Header(None)
):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")

    # yt-dlp --no-js-runtimes --js-runtimes node --remote-components ejs:github -f "ba[ext=m4a]/ba" -x --audio-format m4a --embed-thumbnail --embed-metadata --convert-thumbnails jpg --cookies-from-browser firefox "URL"
    
    # We'll use a temp directory to catch the output file
    with tempfile.TemporaryDirectory() as tmpdir:
        # yt-dlp command
        cmd = [
            "yt-dlp",
            "--no-js-runtimes",
            "--js-runtimes", "node",
            "--remote-components", "ejs:github",
            "-f", "ba[ext=m4a]/ba",
            "-x",
            "--audio-format", "m4a",
            "--embed-thumbnail",
            "--embed-metadata",
            "--convert-thumbnails", "jpg",
            "--cookies-from-browser", "firefox",
            "--paths", tmpdir,
            url
        ]
        
        try:
            process = subprocess.run(cmd, capture_output=True, text=True)
            if process.returncode != 0:
                raise HTTPException(status_code=500, detail=f"yt-dlp failed: {process.stderr}")
            
            # Find the downloaded file in tmpdir
            downloaded_files = os.listdir(tmpdir)
            if not downloaded_files:
                raise HTTPException(status_code=500, detail="No file downloaded by yt-dlp")
            
            # Get the first m4a or mp3 etc file
            audio_files = [f for f in downloaded_files if any(f.lower().endswith(ext) for ext in [".m4a", ".mp3", ".flac", ".wav"])]
            if not audio_files:
                 raise HTTPException(status_code=500, detail="No audio file found after yt-dlp download")
            
            orig_filename = audio_files[0]
            final_filename = filename if filename else orig_filename
            if not any(final_filename.lower().endswith(ext) for ext in [".m4a", ".mp3", ".flac", ".wav"]):
                final_filename += ".m4a"

            dest_path = os.path.join(settings.DOWNLOADED_DIR, final_filename)
            shutil.move(os.path.join(tmpdir, orig_filename), dest_path)
            
            # Record uploader with title
            display_title = final_filename.rsplit('.', 1)[0]
            user_service.record_upload(
                x_username, 
                final_filename, 
                display_title, 
                source="youtube", 
                original_filename=orig_filename, 
                youtube_url=url
            )
            
            return {"message": "Download successful", "filename": final_filename}
            
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=9000)