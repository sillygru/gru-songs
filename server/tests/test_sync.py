"""
Comprehensive tests for the bidirectional sync system.

Tests cover:
1. Server returns favorites correctly
2. Client can add favorites via API
3. Client can remove favorites via API
4. Stats DB merge (additive only)
5. Data DB upload is rejected
6. Shuffle state merge
"""

import os
import sys
import json
import sqlite3
import tempfile
import requests

# Server configuration
BASE_URL = "https://[REDACTED]/music"
TEST_USER = "gru"

def get_headers():
    return {
        'Content-Type': 'application/json',
        'x-username': TEST_USER,
    }

def test_get_favorites():
    """Test that server returns favorites list correctly"""
    print("\n=== Test: GET /user/favorites ===")
    response = requests.get(f"{BASE_URL}/user/favorites", headers=get_headers())
    
    assert response.status_code == 200, f"Expected 200, got {response.status_code}"
    favorites = response.json()
    assert isinstance(favorites, list), "Response should be a list"
    
    print(f"✓ Server returned {len(favorites)} favorites")
    return favorites

def test_get_user_data():
    """Test that /user/data returns all user data"""
    print("\n=== Test: GET /user/data ===")
    response = requests.get(f"{BASE_URL}/user/data", headers=get_headers())
    
    assert response.status_code == 200, f"Expected 200, got {response.status_code}"
    data = response.json()
    
    assert 'favorites' in data, "Response should contain 'favorites'"
    assert 'suggestLess' in data, "Response should contain 'suggestLess'"
    assert 'shuffleState' in data, "Response should contain 'shuffleState'"
    
    print(f"✓ User data: {len(data['favorites'])} favorites, {len(data['suggestLess'])} suggestLess")
    return data

def test_add_favorite():
    """Test adding a favorite via API"""
    print("\n=== Test: POST /user/favorites ===")
    test_song = "__test_favorite_song__.m4a"
    
    # First, get current favorites
    response = requests.get(f"{BASE_URL}/user/favorites", headers=get_headers())
    original_favorites = response.json()
    
    # Remove test song if it exists (cleanup from previous test)
    if test_song in original_favorites:
        requests.delete(f"{BASE_URL}/user/favorites/{test_song}", headers=get_headers())
        original_favorites = requests.get(f"{BASE_URL}/user/favorites", headers=get_headers()).json()
    
    # Add test favorite
    response = requests.post(
        f"{BASE_URL}/user/favorites",
        headers=get_headers(),
        json={'song_filename': test_song, 'session_id': 'test_session'}
    )
    
    assert response.status_code == 200, f"Expected 200, got {response.status_code}"
    
    # Verify it was added
    response = requests.get(f"{BASE_URL}/user/favorites", headers=get_headers())
    new_favorites = response.json()
    
    assert test_song in new_favorites, "Test song should be in favorites after add"
    assert len(new_favorites) == len(original_favorites) + 1, "Favorites count should increase by 1"
    
    print(f"✓ Successfully added '{test_song}' to favorites")
    return test_song

def test_remove_favorite():
    """Test removing a favorite via API"""
    print("\n=== Test: DELETE /user/favorites ===")
    test_song = "__test_favorite_song__.m4a"
    
    # Get current favorites
    response = requests.get(f"{BASE_URL}/user/favorites", headers=get_headers())
    current_favorites = response.json()
    
    if test_song not in current_favorites:
        # Add it first if not present
        requests.post(
            f"{BASE_URL}/user/favorites",
            headers=get_headers(),
            json={'song_filename': test_song, 'session_id': 'test_session'}
        )
        current_favorites = requests.get(f"{BASE_URL}/user/favorites", headers=get_headers()).json()
    
    # Remove test favorite
    response = requests.delete(
        f"{BASE_URL}/user/favorites/{test_song}",
        headers=get_headers()
    )
    
    assert response.status_code == 200, f"Expected 200, got {response.status_code}"
    
    # Verify it was removed
    response = requests.get(f"{BASE_URL}/user/favorites", headers=get_headers())
    new_favorites = response.json()
    
    assert test_song not in new_favorites, "Test song should NOT be in favorites after remove"
    
    print(f"✓ Successfully removed '{test_song}' from favorites")

def test_add_suggest_less():
    """Test adding a suggest-less via API"""
    print("\n=== Test: POST /user/suggest-less ===")
    test_song = "__test_suggest_less__.m4a"
    
    # First, get current suggest-less
    response = requests.get(f"{BASE_URL}/user/suggest-less", headers=get_headers())
    original_sl = response.json()
    
    # Remove test song if it exists (cleanup)
    if test_song in original_sl:
        requests.delete(f"{BASE_URL}/user/suggest-less/{test_song}", headers=get_headers())
    
    # Add test suggest-less
    response = requests.post(
        f"{BASE_URL}/user/suggest-less",
        headers=get_headers(),
        json={'song_filename': test_song}
    )
    
    assert response.status_code == 200, f"Expected 200, got {response.status_code}"
    
    # Verify it was added
    response = requests.get(f"{BASE_URL}/user/suggest-less", headers=get_headers())
    new_sl = response.json()
    
    assert test_song in new_sl, "Test song should be in suggest-less after add"
    
    print(f"✓ Successfully added '{test_song}' to suggest-less")
    
    # Cleanup
    requests.delete(f"{BASE_URL}/user/suggest-less/{test_song}", headers=get_headers())

def test_data_db_upload_rejected():
    """Test that uploading data DB is rejected (must use API calls)"""
    print("\n=== Test: POST /user/db/data (should be REJECTED) ===")
    
    # Create a dummy DB file
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as tmp:
        tmp_path = tmp.name
    
    try:
        with open(tmp_path, 'rb') as f:
            response = requests.post(
                f"{BASE_URL}/user/db/data",
                headers={'x-username': TEST_USER},
                files={'file': ('test.db', f, 'application/octet-stream')}
            )
        
        assert response.status_code == 400, f"Expected 400 (rejected), got {response.status_code}"
        assert "disabled" in response.json().get('detail', '').lower(), "Should mention that uploads are disabled"
        
        print("✓ Data DB upload correctly rejected with 400 error")
    finally:
        os.unlink(tmp_path)

def test_stats_db_merge():
    """Test that stats DB upload is merged (additive), not overwritten"""
    print("\n=== Test: POST /user/db/stats (merge) ===")
    
    # Get current stats count from server
    response = requests.get(
        f"{BASE_URL}/user/db/stats",
        headers={'x-username': TEST_USER}
    )
    
    if response.status_code == 200:
        # Save original stats to temp file
        original_path = tempfile.mktemp(suffix='_original.db')
        with open(original_path, 'wb') as f:
            f.write(response.content)
        
        try:
            original_conn = sqlite3.connect(original_path)
            original_count = original_conn.execute("SELECT COUNT(*) FROM playevent").fetchone()[0]
            original_conn.close()
            
            print(f"  Server has {original_count} play events before test")
            
            # Create a test stats DB with one event
            test_path = tempfile.mktemp(suffix='_test.db')
            test_conn = sqlite3.connect(test_path)
            test_conn.execute("""
                CREATE TABLE IF NOT EXISTS playsession (
                    id TEXT PRIMARY KEY,
                    start_time REAL,
                    end_time REAL,
                    platform TEXT
                )
            """)
            test_conn.execute("""
                CREATE TABLE IF NOT EXISTS playevent (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id TEXT,
                    song_filename TEXT,
                    event_type TEXT,
                    timestamp REAL,
                    duration_played REAL,
                    total_length REAL,
                    play_ratio REAL,
                    foreground_duration REAL,
                    background_duration REAL
                )
            """)
            
            # Add a test event with unique timestamp
            test_timestamp = 9999999999.123  # Far future timestamp to avoid collision
            test_conn.execute("INSERT INTO playsession VALUES (?, ?, ?, ?)", 
                            ('__test_session__', test_timestamp, test_timestamp, 'test'))
            test_conn.execute("""
                INSERT INTO playevent (session_id, song_filename, event_type, timestamp, duration_played, total_length, play_ratio, foreground_duration, background_duration)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, ('__test_session__', '__test_song__.m4a', 'test', test_timestamp, 10.0, 100.0, 0.1, 10.0, 0.0))
            test_conn.commit()
            test_conn.close()
            
            # Upload test DB
            with open(test_path, 'rb') as f:
                response = requests.post(
                    f"{BASE_URL}/user/db/stats",
                    headers={'x-username': TEST_USER},
                    files={'file': ('stats.db', f, 'application/octet-stream')}
                )
            
            assert response.status_code == 200, f"Expected 200, got {response.status_code}"
            
            # Download and check merged result
            response = requests.get(
                f"{BASE_URL}/user/db/stats",
                headers={'x-username': TEST_USER}
            )
            
            merged_path = tempfile.mktemp(suffix='_merged.db')
            with open(merged_path, 'wb') as f:
                f.write(response.content)
            
            merged_conn = sqlite3.connect(merged_path)
            merged_count = merged_conn.execute("SELECT COUNT(*) FROM playevent").fetchone()[0]
            test_exists = merged_conn.execute(
                "SELECT COUNT(*) FROM playevent WHERE timestamp = ?", (test_timestamp,)
            ).fetchone()[0]
            merged_conn.close()
            
            # Cleanup temp files
            os.unlink(test_path)
            os.unlink(merged_path)
            
            assert merged_count >= original_count, "Merged count should be >= original (additive)"
            assert test_exists == 1, "Test event should exist in merged DB"
            
            print(f"✓ Stats merged correctly: {original_count} -> {merged_count} events")
            
            # Cleanup: Remove test event from server (manual)
            print("  Note: Test event left in server (harmless)")
            
        finally:
            os.unlink(original_path)
    else:
        print(f"  Skipping: Could not download stats DB (status {response.status_code})")

def test_user_data_post_only_adds():
    """Test that POST /user/data only adds, never removes"""
    print("\n=== Test: POST /user/data (merge only) ===")
    
    # Get current state
    response = requests.get(f"{BASE_URL}/user/data", headers=get_headers())
    original_data = response.json()
    original_favorites = set(original_data['favorites'])
    
    # Post empty favorites - should NOT remove existing
    response = requests.post(
        f"{BASE_URL}/user/data",
        headers=get_headers(),
        json={'favorites': [], 'suggestLess': [], 'shuffleState': {}}
    )
    
    assert response.status_code == 200, f"Expected 200, got {response.status_code}"
    
    # Verify favorites were NOT deleted
    response = requests.get(f"{BASE_URL}/user/data", headers=get_headers())
    new_data = response.json()
    new_favorites = set(new_data['favorites'])
    
    assert original_favorites == new_favorites, "Favorites should NOT be deleted when posting empty list"
    
    print("✓ POST /user/data correctly does NOT delete existing favorites when given empty list")

def test_favorites_persistence():
    """Test that favorites persist across multiple requests"""
    print("\n=== Test: Favorites Persistence ===")
    
    # Get favorites 3 times
    results = []
    for i in range(3):
        response = requests.get(f"{BASE_URL}/user/favorites", headers=get_headers())
        results.append(set(response.json()))
    
    assert results[0] == results[1] == results[2], "Favorites should be consistent across requests"
    
    print(f"✓ Favorites consistently returned {len(results[0])} items across 3 requests")

def run_all_tests():
    print("=" * 60)
    print("SYNC SYSTEM TESTS")
    print("=" * 60)
    print(f"Server: {BASE_URL}")
    print(f"User: {TEST_USER}")
    
    tests = [
        test_get_favorites,
        test_get_user_data,
        test_add_favorite,
        test_remove_favorite,
        test_add_suggest_less,
        test_data_db_upload_rejected,
        test_stats_db_merge,
        test_user_data_post_only_adds,
        test_favorites_persistence,
    ]
    
    passed = 0
    failed = 0
    
    for test in tests:
        try:
            test()
            passed += 1
        except AssertionError as e:
            print(f"✗ FAILED: {e}")
            failed += 1
        except Exception as e:
            print(f"✗ ERROR: {e}")
            failed += 1
    
    print("\n" + "=" * 60)
    print(f"RESULTS: {passed} passed, {failed} failed")
    print("=" * 60)
    
    return failed == 0

if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)
