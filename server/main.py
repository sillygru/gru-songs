from fastapi import FastAPI, HTTPException, Header
from fastapi.responses import Response
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from settings import settings
from services import music_service
from user_service import user_service
import asyncio
from fastapi import FastAPI, HTTPException, Header
from fastapi.responses import Response
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from settings import settings
from services import music_service
from user_service import user_service
from models import UserCreate, UserLogin, UserUpdate, StatsEntry, UserProfileUpdate, PlaylistCreate, PlaylistAddSong, FavoriteRequest

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/stream", StaticFiles(directory=settings.MUSIC_DIR), name="stream")
app.mount("/lyrics", StaticFiles(directory=settings.LYRICS_DIR), name="lyrics")

# --- Background Task for Stats Flushing ---

@app.on_event("startup")
async def startup_event():
    asyncio.create_task(periodic_flush())

@app.on_event("shutdown")
async def shutdown_event():
    user_service.flush_stats()

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

@app.get("/lyrics-embedded/{filename}")
def get_embedded_lyrics(filename: str):
    lyrics = music_service.get_embedded_lyrics(filename)
    if not lyrics:
        raise HTTPException(status_code=404, detail="No embedded lyrics found")
    
    return Response(content=str(lyrics), media_type="text/plain")

@app.get("/cover/{filename}")
def get_cover(filename: str):
    data, mime = music_service.get_cover_data(filename)
    if not data:
        raise HTTPException(status_code=404, detail="No cover found in metadata")
    
    return Response(content=data, media_type=mime)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=9000)
