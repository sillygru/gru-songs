import os
from sqlmodel import Session, select, func
from database_manager import db_manager
from db_models import PlayEvent
from settings import settings

def analyze_full_db(username: str):
    print(f"=== FULL DB ANALYSIS FOR {username} ===")
    with Session(db_manager.get_user_stats_engine(username)) as session:
        # 1. Overall counts
        total_events = session.exec(select(func.count(PlayEvent.id))).one()
        skips = session.exec(select(func.count(PlayEvent.id)).where(PlayEvent.event_type == "skip")).one()
        completes = session.exec(select(func.count(PlayEvent.id)).where(PlayEvent.event_type == "complete")).one()
        listens = session.exec(select(func.count(PlayEvent.id)).where(PlayEvent.event_type == "listen")).one()

        print(f"Total Events: {total_events}")
        print(f"  - Skips:     {skips}")
        print(f"  - Completes: {completes}")
        print(f"  - Listens:   {listens}")

        # 2. Analyze "Fake Skips" (Skips that are actually completions)
        fake_skips = session.exec(
            select(PlayEvent)
            .where(PlayEvent.event_type == "skip")
            .where(PlayEvent.play_ratio >= 0.9)
        ).all()
        
        print(f"\nFound {len(fake_skips)} skips with ratio >= 0.9 (Fake Skips)")
        
        # Distribution of ratios for skips
        print("\nRatio distribution for 'skip' events:")
        ranges = [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0, 1.1]
        for i in range(len(ranges)-1):
            low = ranges[i]
            high = ranges[i+1]
            count = session.exec(
                select(func.count(PlayEvent.id))
                .where(PlayEvent.event_type == "skip")
                .where(PlayEvent.play_ratio > low)
                .where(PlayEvent.play_ratio <= high)
            ).one()
            print(f"  {low:4.2f} - {high:4.2f}: {count}")

        # 3. Sample of extremely high ratio skips
        high_skips = sorted(fake_skips, key=lambda x: x.play_ratio, reverse=True)[:10]
        print("\nTop 10 High-Ratio Skips:")
        for e in high_skips:
            print(f"  Ratio: {e.play_ratio:5.2f} | Dur: {e.duration_played:6.1f}s | Tot: {e.total_length:6.1f}s | Song: {e.song_filename}")

if __name__ == "__main__":
    analyze_full_db("gru")