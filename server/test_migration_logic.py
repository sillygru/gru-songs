import os
import shutil
import tempfile
import sys
import unittest
import json
from sqlmodel import Session, select

# Ensure we can import from server directory
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from db_models import PlayEvent, PlaySession
from database_manager import db_manager
from migrate_skips_logic import rebuild_user_stats

class TestMigrationComprehensive(unittest.TestCase):
    def setUp(self):
        # Create temp dir
        self.test_dir = tempfile.mkdtemp()
        self.users_dir = os.path.join(self.test_dir, "users")
        os.makedirs(self.users_dir)
        
        # Override db_manager path
        self.original_users_dir = db_manager.users_dir
        db_manager.users_dir = self.users_dir
        
        # Patch settings
        from settings import settings
        self.original_settings_users_dir = settings.USERS_DIR
        settings.USERS_DIR = self.users_dir

    def tearDown(self):
        # Restore
        db_manager.users_dir = self.original_users_dir
        from settings import settings
        settings.USERS_DIR = self.original_settings_users_dir
        
        shutil.rmtree(self.test_dir)

    def test_migration_edge_cases(self):
        username = "test_user_comp"
        db_manager.init_user_dbs(username)
        
        session_id = "sess_comp"
        
        # Test Data Scenarios
        scenarios = [
            # 1. Standard "Underrun" (The main goal)
            # Song: 100s, Played: 95s (Diff 5s) -> Should be COMPLETE
            {"file": "underrun.mp3", "type": "skip", "total": 100.0, "played": 95.0, "expect": "complete"},

            # 2. "Overrun" (Played longer than duration)
            # Song: 100s, Played: 105s (Diff -5s) -> Should be COMPLETE
            {"file": "overrun.mp3", "type": "skip", "total": 100.0, "played": 105.0, "expect": "complete"},

            # 3. Exact 10s Boundary
            # Song: 100s, Played: 90s (Diff 10s) -> Should be COMPLETE
            {"file": "boundary_exact.mp3", "type": "skip", "total": 100.0, "played": 90.0, "expect": "complete"},

            # 4. Just Outside Boundary (10.1s)
            # Song: 100s, Played: 89.9s (Diff 10.1s) -> Should stay SKIP
            {"file": "boundary_miss.mp3", "type": "skip", "total": 100.0, "played": 89.9, "expect": "skip"},

            # 5. Normal Early Skip
            # Song: 100s, Played: 10s (Diff 90s) -> Should stay SKIP
            {"file": "early_skip.mp3", "type": "skip", "total": 100.0, "played": 10.0, "expect": "skip"},
        ]

        # Insert Data
        with Session(db_manager.get_user_stats_engine(username)) as session:
            session.add(PlaySession(id=session_id, start_time=1000, end_time=2000))
            
            for i, sc in enumerate(scenarios):
                session.add(PlayEvent(
                    session_id=session_id,
                    song_filename=sc["file"],
                    event_type=sc["type"],
                    timestamp=1000 + i,
                    duration_played=sc["played"],
                    total_length=sc["total"],
                    play_ratio=sc["played"]/sc["total"]
                ))
            session.commit()
            
        # Run Migration
        rebuild_user_stats(username)
        
        # Verify SQL Data
        with Session(db_manager.get_user_stats_engine(username)) as session:
            events = session.exec(select(PlayEvent).order_by(PlayEvent.timestamp)).all()
            
            print("\n--- Test Results ---")
            for i, event in enumerate(events):
                scenario = scenarios[i]
                status = "PASS" if event.event_type == scenario["expect"] else "FAIL"
                print(f"[{status}] {scenario['file']}: Played {scenario['played']}/{scenario['total']} (Diff {scenario['total']-scenario['played']:.1f}s) -> Got {event.event_type.upper()}, Expected {scenario['expect'].upper()}")
                
                self.assertEqual(event.event_type, scenario["expect"], 
                                 f"Failed for {scenario['file']}")

        # Verify JSON Stats Summary
        final_path = os.path.join(self.users_dir, f"{username}_final_stats.json")
        with open(final_path, "r") as f:
            data = json.load(f)
        
        # Expected: 3 completions (Underrun, Overrun, Boundary) and 2 skips (Miss, Early)
        # However, note that "boundary_miss" played 89.9/100 = 0.89 ratio.
        # My logic counts ratio > 0.8 as a "meaningful play" in the JSON stats (total_songs_played),
        # even if the event_type stays 'skip'.
        # But 'total_skipped' only increments if ratio < 0.2.
        
        # Let's break down the JSON expectations:
        # 1. underrun (Complete) -> Played +1
        # 2. overrun (Complete) -> Played +1
        # 3. boundary (Complete) -> Played +1
        # 4. miss (Skip, ratio 0.89) -> Played +1 (due to ratio > 0.8 logic), Skipped +0 (ratio > 0.2)
        # 5. early (Skip, ratio 0.1) -> Played +0, Skipped +1 (ratio < 0.2)
        
        print("\n--- JSON Stats Check ---")
        print(f"Total Played: {data['total_songs_played']} (Expected 4)")
        print(f"Total Skipped: {data['total_skipped']} (Expected 1)")
        
        self.assertEqual(data["total_songs_played"], 4)
        self.assertEqual(data["total_skipped"], 1)

if __name__ == "__main__":
    unittest.main()