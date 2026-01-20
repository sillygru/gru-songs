import os
from sqlalchemy.orm import Session
from sqlalchemy import select, delete
from database_manager import db_manager
from db_models import PlayEvent
from settings import settings
from migrate_stats import migrate_user_stats

def coalesce_user_events(username: str):
    print(f"Starting event coalescing for user: {username}")
    
    stats_db_path = os.path.join(settings.USERS_DIR, f"{username}_stats.db")
    if not os.path.exists(stats_db_path):
        print(f"No stats database found for {username}")
        return

    with Session(db_manager.get_user_stats_engine(username)) as session:
        # 2. Fetch all events sorted by timestamp
        # We also sort by session_id to group them, but timestamp is the main driver for "consecutive"
        raw_events = session.execute(select(PlayEvent).order_by(PlayEvent.timestamp)).scalars().all()
        
        if not raw_events:
            print("No events found.")
            return

        print(f"Found {len(raw_events)} raw events.")
        
        coalesced_events = []
        current_merged = None

        for event in raw_events:
            if current_merged is None:
                # Start new group
                current_merged = _clone_event(event)
                continue

            # Check if we should merge
            # Same session, same song
            # AND ideally consecutive in time, but our "consecutive" assumption 
            # is handled by the loop order.
            if (event.session_id == current_merged.session_id and 
                event.song_filename == current_merged.song_filename):
                
                # Merge logic
                current_merged.duration_played += event.duration_played
                
                # Handle FG/BG
                fg1 = current_merged.foreground_duration or 0.0
                bg1 = current_merged.background_duration or 0.0
                fg2 = event.foreground_duration or 0.0
                bg2 = event.background_duration or 0.0
                
                current_merged.foreground_duration = fg1 + fg2
                current_merged.background_duration = bg1 + bg2
                
                # Update metadata from latest
                current_merged.event_type = event.event_type
                current_merged.timestamp = event.timestamp
                # play_ratio needs recalculation based on total_length
                # We'll do it at the end of the merge
                
            else:
                # Push current and start new
                coalesced_events.append(current_merged)
                current_merged = _clone_event(event)
        
        # Push final
        if current_merged:
            coalesced_events.append(current_merged)

        # 3. Recalculate Ratios for coalesced events
        for evt in coalesced_events:
            if evt.total_length > 0:
                evt.play_ratio = evt.duration_played / evt.total_length
                # Retroactively fix "complete" status if close enough
                if (evt.total_length - evt.duration_played) <= 10.0:
                     if evt.event_type == 'skip':
                         evt.event_type = 'complete'
            else:
                evt.play_ratio = 0.0

        print(f"Coalesced into {len(coalesced_events)} events (Reduced by {len(raw_events) - len(coalesced_events)})")

        # 4. Replace in DB
        # Delete all existing
        session.execute(delete(PlayEvent))
        session.commit()
        
        # Add new
        for evt in coalesced_events:
            session.add(evt)
        
        session.commit()
        print("Database updated.")

    # 5. Refresh JSON stats
    migrate_user_stats(username)

def _clone_event(source: PlayEvent) -> PlayEvent:
    # Create a new instance detached from session
    return PlayEvent(
        session_id=source.session_id,
        song_filename=source.song_filename,
        event_type=source.event_type,
        timestamp=source.timestamp,
        duration_played=source.duration_played,
        total_length=source.total_length,
        play_ratio=source.play_ratio,
        foreground_duration=source.foreground_duration,
        background_duration=source.background_duration
    )

def main():
    users = []
    if not os.path.exists(settings.USERS_DIR): 
        print("Users directory not found.")
        return

    for f in os.listdir(settings.USERS_DIR):
        if f.endswith("_data.db"): 
            users.append(f[:-8]) # strip "_data.db"
    
    print(f"Found users: {users}")
    for user in users:
        coalesce_user_events(user)

if __name__ == "__main__":
    main()