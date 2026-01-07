import os
import io
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, Response
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from mutagen import File

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

MUSIC_DIR = "/home/sillygru/Documents/music/Songs"
LYRICS_DIR = "/home/sillygru/Documents/music/Lyrics"

app.mount("/stream", StaticFiles(directory=MUSIC_DIR), name="stream")
app.mount("/lyrics", StaticFiles(directory=LYRICS_DIR), name="lyrics")

@app.get("/list-songs")
def list_songs():
    songs = []
    if not os.path.exists(MUSIC_DIR):
        return {"error": f"Directory not found: {MUSIC_DIR}"}

    for file in os.listdir(MUSIC_DIR):
        if file.lower().endswith((".m4a", ".mp3", ".flac")):
            path = os.path.join(MUSIC_DIR, file)
            # Use easy=True for unified title/artist access across formats
            audio = File(path, easy=True)
            
            display_name = file.rsplit('.', 1)[0]
            title = display_name
            artist = "Unknown"
            album = "Unknown Album"

            if audio:
                title = audio.get("title", [display_name])[0]
                artist = audio.get("artist", ["Unknown"])[0]
                album = audio.get("album", ["Unknown Album"])[0]

            lrc_file = f"{display_name}.lrc"
            has_lrc = os.path.exists(os.path.join(LYRICS_DIR, lrc_file))
            
            lyrics_url = f"/lyrics/{lrc_file}" if has_lrc else None
            
            # Fallback to embedded lyrics if no .lrc file exists
            if not lyrics_url:
                raw_audio = File(path)
                if raw_audio:
                    # Check for common embedded lyrics tags
                    if "\xa9lyr" in raw_audio or any(k.startswith("USLT") for k in raw_audio.keys()):
                        lyrics_url = f"/lyrics-embedded/{file}"
            
            songs.append({
                "title": str(title),
                "artist": str(artist),
                "album": str(album),
                "filename": file,
                "url": f"/stream/{file}",
                "lyrics_url": lyrics_url,
                "cover_url": f"/cover/{file}"
            })
    
    return sorted(songs, key=lambda x: x['title'])

@app.get("/lyrics-embedded/{filename}")
def get_embedded_lyrics(filename: str):
    path = os.path.join(MUSIC_DIR, filename)
    if not os.path.exists(path):
        raise HTTPException(status_code=404)
    
    audio = File(path)
    if not audio:
        raise HTTPException(status_code=404)

    lyrics = None
    if "\xa9lyr" in audio:
        lyrics = audio["\xa9lyr"][0]
    else:
        for key in audio.keys():
            if key.startswith("USLT"):
                lyrics = audio[key].text
                if isinstance(lyrics, list):
                    lyrics = lyrics[0]
                break
    
    if not lyrics:
        raise HTTPException(status_code=404, detail="No embedded lyrics found")
    
    return Response(content=str(lyrics), media_type="text/plain")

@app.get("/cover/{filename}")
def get_cover(filename: str):
    path = os.path.join(MUSIC_DIR, filename)
    if not os.path.exists(path):
        raise HTTPException(status_code=404)
    
    audio = File(path)
    if not audio:
        raise HTTPException(status_code=404)

    # Handle MP3 (ID3)
    for key in audio.keys():
        if key.startswith("APIC"):
            return Response(content=audio[key].data, media_type=audio[key].mime)
    
    # Handle M4A (MP4)
    if "covr" in audio:
        return Response(content=audio["covr"][0], media_type="image/jpeg")

    # Handle FLAC
    if hasattr(audio, 'pictures') and audio.pictures:
        return Response(content=audio.pictures[0].data, media_type=audio.pictures[0].mime)

    raise HTTPException(status_code=404, detail="No cover found in metadata")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=9000)