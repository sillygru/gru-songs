from fastapi import FastAPI, HTTPException, Header, UploadFile, File
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from typing import Dict, Any, List, Optional
import os
import shutil
import asyncio
from contextlib import asynccontextmanager
from multiprocessing import Process, Queue

from settings import settings
from services import music_service
from user_service import user_service
from backup_service import backup_service
from discord_bot import run_bot
from models import UserCreate, UserLogin, UserUpdate, StatsEntry, UserProfileUpdate, FavoriteRequest

# Global queue and process for discord bot
discord_queue = Queue()
command_queue = Queue()
bot_process = None

async def listen_for_commands():
    while True:
        try:
            # Check for commands from bot process
            while not command_queue.empty():
                cmd_data = command_queue.get_nowait()
                if not cmd_data: continue
                
                cmd_type = cmd_data.get("command")
                if cmd_type == "backup":
                    reset = cmd_data.get("reset", False)
                    requester = cmd_data.get("requester", "Unknown")
                    discord_queue.put(f"🔄 Backup triggered by {requester} (Reset Timer: {reset})...")
                    
                    success, msg = await backup_service.trigger_backup(reset_timer=reset)
                    
                    # Log result back to discord
                    # Result is already logged by backup_service._log which goes to discord_queue
                    # But we can add extra confirmation if needed
                    pass
                    
        except Exception as e:
            print(f"Error in command listener: {e}")
            
        await asyncio.sleep(1)

@asynccontextmanager
async def lifespan(app: FastAPI):
    global bot_process
    # Startup logic
    backup_service.log_event("STARTUP")
    user_service.set_discord_queue(discord_queue)
    backup_service.set_discord_queue(discord_queue)
    
    # Start Discord Bot in a separate process
    bot_process = Process(target=run_bot, args=(discord_queue, command_queue), daemon=True)
    bot_process.start()
    
    discord_queue.put(f"🖥️ Server starting up... (v{settings.VERSION})")
    
    asyncio.create_task(periodic_flush())
    asyncio.create_task(backup_service.start_scheduler())
    asyncio.create_task(listen_for_commands())
    yield
    # Shutdown logic
    backup_service.log_event("SHUTDOWN")
    if bot_process:
        try:
            discord_queue.put("🛑 Server shutting down...")
            discord_queue.put(None) # Sentinel for graceful exit
            # Give the bot a moment to process the message
            await asyncio.sleep(0.5)
        except:
            pass
        
        bot_process.terminate()
        bot_process.join(timeout=2)
        if bot_process.is_alive():
            bot_process.kill()
            bot_process.join()

    user_service.flush_stats()

app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Custom stream route removed as server is now offline-first for media

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

@app.get("/stats/fun")
def get_fun_stats(x_username: str = Header(None)):
    if not x_username:
         raise HTTPException(status_code=401, detail="User not authenticated")
    return user_service.get_fun_stats(x_username)


# --- User Data Routes (Comprehensive Sync) ---

@app.get("/user/data")
def get_user_data(x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")

    # Get all user data in one call
    favorites = user_service.get_favorites(x_username)
    suggest_less = user_service.get_suggest_less(x_username)
    shuffle_state = user_service.get_stats_summary(x_username).get("shuffle_state", {})

    return {
        "favorites": favorites,
        "suggestLess": suggest_less,
        "shuffleState": shuffle_state
    }

@app.post("/user/data")
def update_user_data(data: Dict[str, Any], x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")

    # Update all user data in one call
    favorites = data.get("favorites", [])
    suggest_less = data.get("suggestLess", [])
    shuffle_state = data.get("shuffleState", {})

    # MERGE favorites - only ADD new ones
    current_favorites = set(user_service.get_favorites(x_username))
    new_favorites = set(favorites)

    for filename in new_favorites - current_favorites:
        user_service.add_favorite_without_stats(x_username, filename)

    # MERGE suggest less
    current_suggest_less = set(user_service.get_suggest_less(x_username))
    new_suggest_less = set(suggest_less)

    for filename in new_suggest_less - current_suggest_less:
        user_service.add_suggest_less(x_username, filename)

    # Update shuffle state
    if shuffle_state:
        user_service.update_shuffle_state(x_username, shuffle_state)

    return {"status": "updated"}

# --- Legacy Favorites Routes (for backward compatibility) ---

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
def add_suggest_less(req: FavoriteRequest, x_username: str = Header(None)):
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


# --- User DB & Stats Mirroring Routes ---

@app.get("/user/db/{db_type}")
async def download_user_db(db_type: str, x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")
    
    # Force flush to ensure DB is up to date before download
    user_service.flush_stats()
    
    filename = ""
    if db_type == "stats":
        filename = f"{x_username}_stats.db"
    elif db_type == "data":
        filename = f"{x_username}_data.db"
    elif db_type == "final_stats":
        filename = f"{x_username}_final_stats.json"
    else:
        raise HTTPException(status_code=400, detail="Invalid DB type")
        
    path = os.path.join(settings.USERS_DIR, filename)
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="DB file not found")
        
    return FileResponse(path)

@app.post("/user/db/{db_type}")
async def upload_user_db(db_type: str, file: UploadFile = File(...), x_username: str = Header(None)):
    if not x_username:
        raise HTTPException(status_code=401, detail="User not authenticated")

    filename = ""
    if db_type == "stats":
        filename = f"{x_username}_stats.db"
    elif db_type == "data":
        filename = f"{x_username}_data.db"
    elif db_type == "final_stats":
        filename = f"{x_username}_final_stats.json"
    else:
        raise HTTPException(status_code=400, detail="Invalid DB type")

    path = os.path.join(settings.USERS_DIR, filename)
    
    # Save uploaded file
    with open(path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    return {"message": f"{db_type} updated"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=9000)