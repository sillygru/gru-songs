from fastapi.testclient import TestClient
from main import app
import os
from unittest.mock import MagicMock, patch

client = TestClient(app)

# Mock the music service to avoid filesystem errors
@patch("services.music_service.get_embedded_lyrics")
def test_embedded_lyrics_cache_header(mock_get_lyrics):
    mock_get_lyrics.return_value = "La la la"
    response = client.get("/lyrics-embedded/test_song.mp3")
    assert response.status_code == 200
    assert "Cache-Control" in response.headers
    assert response.headers["Cache-Control"] == "public, max-age=31536000, immutable"

@patch("services.music_service.get_cover_data")
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
