import os
import json
from sqlmodel import Session, select, func
from database_manager import db_manager
from db_models import PlaySession, PlayEvent
from settings import settings

def migrate_user_stats(username: str):
    print(f"Migrating stats for user: {username}")
    
    stats_db_path = os.path.join(settings.USERS_DIR, f"{username}_stats.db")
    if not os.path.exists(stats_db_path):
        print(f"No stats database found for {username}")
        return

    final_stats_path = os.path.join(settings.USERS_DIR, f"{username}_final_stats.json")
    
    # Load existing to preserve shuffle_state if possible
    existing_data = {}
    if os.path.exists(final_stats_path):
        try:
            with open(final_stats_path, "r") as f:
                existing_data = json.load(f)
        except:
            pass

    # Recalculate everything from SQL
    with Session(db_manager.get_user_stats_engine(username)) as session:
        # 1. Sessions and Platforms
        sessions = session.exec(select(PlaySession)).all()
        total_sessions = len(sessions)
        platform_usage = {}
        for s in sessions:
            p = s.platform or "unknown"
            platform_usage[p] = platform_usage.get(p, 0) + 1
        
        # 2. Events breakdown
        total_play_time = session.exec(select(func.sum(PlayEvent.duration_played))).one() or 0.0
        total_fg_time = session.exec(select(func.sum(PlayEvent.foreground_duration))).one() or 0.0
        total_bg_time = session.exec(select(func.sum(PlayEvent.background_duration))).one() or 0.0
        
        # Redefined Logic for Migration
        # Played: Not favorite AND (Ratio > 0.8 OR Type in listen/complete OR (Not favorite AND ratio > 0.2))
        total_songs_played = session.exec(
            select(func.count(PlayEvent.id))
            .where(PlayEvent.event_type != "favorite")
            .where(
                (PlayEvent.play_ratio > 0.8) | 
                (PlayEvent.event_type.in_(["listen", "complete"])) |
                (PlayEvent.play_ratio > 0.2)
            )
        ).one() or 0
        
        total_songs_played_ratio_over_025 = session.exec(
            select(func.count(PlayEvent.id))
            .where(PlayEvent.event_type != "favorite")
            .where(PlayEvent.play_ratio > 0.25)
        ).one() or 0
        
        # Skipped: Type == skip AND Ratio < 0.2
        total_skipped = session.exec(
            select(func.count(PlayEvent.id))
            .where(PlayEvent.event_type == "skip")
            .where(PlayEvent.play_ratio < 0.2)
        ).one() or 0

    # Prepare new clean structure
    new_stats = {
        "total_play_time": round(float(total_play_time), 2),
        "total_sessions": int(total_sessions),
        "platform_usage": platform_usage,
        "total_background_playtime": round(float(total_bg_time), 2),
        "total_foreground_playtime": round(float(total_fg_time), 2),
        "total_songs_played": int(total_songs_played),
        "total_songs_played_ratio_over_025": int(total_songs_played_ratio_over_025),
        "total_skipped": int(total_skipped),
    }

    # Handle shuffle_state
    shuffle_state = existing_data.get("shuffle_state", {})
    if "config" not in shuffle_state:
        old_config = existing_data.get("shuffle_config", {})
        shuffle_state["config"] = {
            "enabled": existing_data.get("shuffle_enabled", True),
            "anti_repeat_enabled": old_config.get("anti_repeat_enabled", True),
            "streak_breaker_enabled": old_config.get("streak_breaker_enabled", True),
            "favorite_multiplier": old_config.get("favorite_multiplier", 1.15),
            "suggest_less_multiplier": old_config.get("suggest_less_multiplier", 0.2),
            "history_limit": old_config.get("history_limit", 50)
        }
    if not shuffle_state.get("history"):
        shuffle_state["history"] = []
    new_stats["shuffle_state"] = shuffle_state

    with open(final_stats_path, "w") as f:
        json.dump(new_stats, f, indent=4)
    print(f"Successfully migrated {username}")

def main():
    users = []
    if not os.path.exists(settings.USERS_DIR): return
    for f in os.listdir(settings.USERS_DIR):
        if f.endswith("_data.db"): users.append(f[:-8])
    for user in users: migrate_user_stats(user)

if __name__ == "__main__":
    main()