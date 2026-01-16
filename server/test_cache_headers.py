import os
import tempfile
import sys
from unittest.mock import MagicMock

# Mock discord before importing main
sys.modules["discord"] = MagicMock()
sys.modules["discord.ext"] = MagicMock()
sys.modules["discord.ext.commands"] = MagicMock()

# Setup env BEFORE importing app/settings
os.environ["GRUSONGS_TESTING"] = "true"
test_dir = tempfile.mkdtemp()
os.environ["MUSIC_DIR"] = os.path.join(test_dir, "music")
os.environ["USERS_DIR"] = os.path.join(test_dir, "users")
os.environ["BACKUPS_DIR"] = os.path.join(test_dir, "backups")

from fastapi.testclient import TestClient
from main import app
from unittest.mock import patch

client = TestClient(app)

from database_manager import db_manager
db_manager.init_global_dbs()

# Mock the music service to avoid filesystem errors
@patch("main.music_service.get_embedded_lyrics")
def test_embedded_lyrics_cache_header(mock_get_lyrics):
    mock_get_lyrics.return_value = "La la la"
    response = client.get("/lyrics-embedded/test_song.mp3")
    assert response.status_code == 200
    assert "Cache-Control" in response.headers
    assert response.headers["Cache-Control"] == "public, max-age=31536000, immutable"

@patch("main.music_service.get_cover_data")
def test_cover_cache_header(mock_get_cover):
    mock_get_cover.return_value = (b"fake_image_data", "image/jpeg")
    response = client.get("/cover/test_song.mp3")
    assert response.status_code == 200
    assert "Cache-Control" in response.headers
    assert response.headers["Cache-Control"] == "public, max-age=31536000, immutable"

if __name__ == "__main__":
    import pytest
    import sys
    # Run pytest programmatically
    sys.exit(pytest.main(["-v", __file__]))
