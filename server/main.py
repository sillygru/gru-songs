from fastapi import FastAPI, HTTPException, Header
from fastapi.responses import Response
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from settings import settings
from services import music_service
from user_service import user_service
from models import UserCreate, UserLogin, UserUpdate, StatsEntry, UserProfileUpdate

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/stream", StaticFiles(directory=settings.MUSIC_DIR), name="stream")
app.mount("/lyrics", StaticFiles(directory=settings.LYRICS_DIR), name="lyrics")

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
        # We allow anonymous stats or just ignore them? For now, require auth as per "EVERYTHING for every user"
        raise HTTPException(status_code=401, detail="User not authenticated")
    
    user_service.append_stats(x_username, stats)
    return {"status": "ok"}


# --- Music Routes ---

@app.get("/list-songs")
def list_songs():
    result = music_service.list_songs()
    if isinstance(result, dict) and "error" in result:
        return result
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
