import os
import json
import shutil
import sys
from sqlmodel import Session

# Fix path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from settings import settings
from database_manager import db_manager
from db_models import GlobalUser, Upload, UserData, Favorite, SuggestLess, PlaySession, PlayEvent

def safe_float(val):
    if val == "unknown" or val is None: return None
    try:
        return float(val)
    except:
        return None

def run_migration():
    users_dir = settings.USERS_DIR
    users_old_dir = os.path.join(os.path.dirname(users_dir), "users_old")

    print(f"Current users dir: {users_dir}")
    print(f"Backup users dir: {users_old_dir}")

    # 1. Rename existing directory
    if os.path.exists(users_dir):
        if os.path.exists(users_old_dir):
            print(f"Error: {users_old_dir} already exists. Remove it first.")
            return
        
        print("Renaming 'users' to 'users_old'...")
        os.rename(users_dir, users_old_dir)
    else:
        print("No 'users' directory. Creating empty structure.")
        os.makedirs(users_dir, exist_ok=True)

    os.makedirs(users_dir, exist_ok=True)
    
    # 2. Init Global DBs
    print("Initializing global databases...")
    db_manager.init_global_dbs()

    # 3. Migrate Uploads
    uploads_path = os.path.join(users_old_dir, "uploads.json")
    if os.path.exists(uploads_path):
        print("Migrating uploads...")
        try:
            with open(uploads_path, "r") as f:
                uploads_data = json.load(f)
            
            with Session(db_manager.get_uploads_engine()) as session:
                for filename, data in uploads_data.items():
                    upload = Upload(
                        filename=filename,
                        uploader_username=data.get("uploader", "Unknown"),
                        title=data.get("title", filename),
                        source=data.get("source", "unknown"),
                        original_filename=data.get("original_filename", filename),
                        youtube_url=data.get("youtube_url"),
                        timestamp=float(data.get("timestamp", 0.0))
                    )
                    session.add(upload)
                session.commit()
        except Exception as e:
            print(f"Failed to migrate uploads: {e}")

    # 4. Migrate Users
    print("Migrating users...")
    for filename in os.listdir(users_old_dir):
        if filename.endswith(".json") and not "_" in filename and filename != "uploads.json":
            username = filename[:-5]
            print(f"  Processing user: {username}")
            
            # Init user DBs
            db_manager.init_user_dbs(username)
            
            # Load User Profile
            user_path = os.path.join(users_old_dir, filename)
            with open(user_path, "r") as f:
                user_data = json.load(f)
            
            # A. Global Users DB
            with Session(db_manager.get_global_users_engine()) as session:
                # Calculate simple summary from old stats if available, or just empty
                # We'll rely on the final_stats json for the detailed summary
                gu = GlobalUser(
                    username=username,
                    created_at=float(user_data.get("created_at", 0))
                )
                session.add(gu)
                session.commit()
            
            # B. [username]_data.db
            with Session(db_manager.get_user_data_engine(username)) as session:
                ud = UserData(
                    username=username,
                    password_hash=user_data["password"],
                    created_at=float(user_data.get("created_at", 0))
                )
                session.add(ud)
                
                for fav in user_data.get("favorites", []):
                    session.add(Favorite(filename=fav))
                    
                for sl in user_data.get("suggest_less", []):
                    session.add(SuggestLess(filename=sl))
                session.commit()

            # D. [username]_stats.db AND [username]_final_stats.json
            stats_path = os.path.join(users_old_dir, f"{username}_stats.json")
            if os.path.exists(stats_path):
                with open(stats_path, "r") as f:
                    stats_blob = json.load(f)
                
                # Write final_stats.json (Just the summary part + total_play_time)
                final_summary = stats_blob.get("total_summary", {})
                final_summary["total_play_time"] = stats_blob.get("total_play_time", 0)
                
                final_json_path = os.path.join(users_dir, f"{username}_final_stats.json")
                with open(final_json_path, "w") as f:
                    json.dump(final_summary, f, indent=4)
                
                # Write Logs to DB
                with Session(db_manager.get_user_stats_engine(username)) as session:
                    for sess in stats_blob.get("sessions", []):
                        db_sess = PlaySession(
                            id=sess["id"],
                            start_time=float(sess["start_time"]),
                            end_time=float(sess["end_time"]),
                            platform=sess.get("platform", "unknown")
                        )
                        session.add(db_sess)
                        session.commit() # Need ID
                        
                        for ev in sess.get("events", []):
                            pe = PlayEvent(
                                session_id=db_sess.id,
                                song_filename=ev["song_filename"],
                                event_type=ev["event_type"],
                                timestamp=safe_float(ev.get("timestamp")),
                                duration_played=safe_float(ev.get("duration_played")),
                                total_length=safe_float(ev.get("total_length")),
                                play_ratio=safe_float(ev.get("play_ratio")),
                                foreground_duration=safe_float(ev.get("foreground_duration")),
                                background_duration=safe_float(ev.get("background_duration"))
                            )
                            session.add(pe)
                    session.commit()

    print("Migration to multi-file DBs complete.")

if __name__ == "__main__":
    run_migration()
