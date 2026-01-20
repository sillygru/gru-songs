import os
import json
import logging
import sys
import shutil
from sqlalchemy.orm import Session
from sqlalchemy import select
from collections import defaultdict

# Ensure we can import from server directory
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from settings import settings
from database_manager import db_manager
from db_models import PlayEvent, PlaySession
from user_service import user_service

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("migration")

def rebuild_user_stats(username):
    logger.info(f"Processing user: {username}")
    
    # 1. Update SQL Data
    changes_count = 0
    with Session(db_manager.get_user_stats_engine(username)) as session:
        events = session.execute(select(PlayEvent)).scalars().all()
        for event in events:
            # Check 10s rule
            # Only affect 'skip' events. 'listen' or others are already fine.
            if event.event_type == 'skip' and event.total_length > 0:
                remaining = event.total_length - event.duration_played
                if remaining <= 10.0:
                    event.event_type = 'complete'
                    session.add(event)
                    changes_count += 1
        session.commit()
    
    logger.info(f"  - Updated {changes_count} events in DB")

    # 2. Rebuild final_stats.json
    # Reset summary
    summary_data = {
        "total_play_time": 0, 
        "total_sessions": 0,
        "total_background_playtime": 0,
        "total_foreground_playtime": 0,
        "total_songs_played": 0,
        "total_songs_played_ratio_over_025": 0,
        "total_skipped": 0,
        "platform_usage": {},
        "shuffle_state": {"config": {}, "history": []}
    }

    # Fetch all events sorted by timestamp
    with Session(db_manager.get_user_stats_engine(username)) as session:
        events = session.execute(select(PlayEvent).order_by(PlayEvent.timestamp)).scalars().all()
        
        processed_sessions = set()
        
        for stats in events:
             # Metrics
            summary_data["total_play_time"] = round(summary_data["total_play_time"] + stats.duration_played, 2)
            
            fg = stats.foreground_duration if stats.foreground_duration is not None else 0
            bg = stats.background_duration if stats.background_duration is not None else 0
            summary_data["total_foreground_playtime"] = round(summary_data["total_foreground_playtime"] + fg, 2)
            summary_data["total_background_playtime"] = round(summary_data["total_background_playtime"] + bg, 2)

            total_length = stats.total_length
            ratio = (stats.duration_played / total_length) if total_length > 0 else 0.0

            is_meaningful_play = (
                stats.event_type in ['complete', 'listen'] or
                ratio > 0.8 or
                (stats.event_type != 'favorite' and ratio > 0.2)
            )

            if stats.event_type != 'favorite' and is_meaningful_play:
                summary_data["total_songs_played"] += 1
            
            if stats.event_type == 'skip' and ratio < 0.2:
                summary_data["total_skipped"] += 1

            # Shuffle history update
            if is_meaningful_play:
                shuffle_state = summary_data.get("shuffle_state", {})
                history = shuffle_state.get("history", [])
                
                new_entry = {"filename": stats.song_filename, "timestamp": stats.timestamp}
                
                # Remove existing entry for this song
                history = [h for h in history if (isinstance(h, dict) and h["filename"] != stats.song_filename) or (isinstance(h, str) and h != stats.song_filename)]
                
                history.insert(0, new_entry)
                
                # Default limit 50 (will be refined by config later)
                history_limit = 50 
                
                if len(history) > history_limit:
                    history = history[:history_limit]
                
                shuffle_state["history"] = history
                summary_data["shuffle_state"] = shuffle_state

            if stats.event_type != "favorite" and ratio > 0.25:
                summary_data["total_songs_played_ratio_over_025"] += 1

    # Re-calculate platform usage and total sessions from PlaySession table
    with Session(db_manager.get_user_stats_engine(username)) as session:
        sessions = session.execute(select(PlaySession)).scalars().all()
        summary_data["total_sessions"] = len(sessions)
        summary_data["platform_usage"] = {}
        for s in sessions:
            p = s.platform or "unknown"
            summary_data["platform_usage"][p] = summary_data["platform_usage"].get(p, 0) + 1
            
    # Preserve Config from old file
    old_summary = user_service._get_summary_no_flush(username)
    if "shuffle_state" in old_summary and "config" in old_summary["shuffle_state"]:
        summary_data["shuffle_state"]["config"] = old_summary["shuffle_state"]["config"]
        # Apply history limit from config if available
        limit = old_summary["shuffle_state"]["config"].get("history_limit", 50)
        if len(summary_data["shuffle_state"]["history"]) > limit:
            summary_data["shuffle_state"]["history"] = summary_data["shuffle_state"]["history"][:limit]

    # Write back
    final_path = user_service._get_final_stats_path(username)
    with open(final_path, "w") as f:
        json.dump(summary_data, f, indent=4)
        
    logger.info(f"  - Rebuilt stats summary for {username}")

def main():
    users_dir = settings.USERS_DIR
    if not os.path.exists(users_dir):
        logger.error(f"Users directory not found: {users_dir}")
        return

    files = os.listdir(users_dir)
    users = []
    for f in files:
        if f.endswith("_data.db"):
            users.append(f.replace("_data.db", ""))
            
    logger.info(f"Found {len(users)} users: {users}")
    
    for user in users:
        try:
            rebuild_user_stats(user)
        except Exception as e:
            logger.error(f"Error processing {user}: {e}", exc_info=True)

if __name__ == "__main__":
    main()