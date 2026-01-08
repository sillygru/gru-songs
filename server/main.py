from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from settings import settings
from services import music_service

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/stream", StaticFiles(directory=settings.MUSIC_DIR), name="stream")
app.mount("/lyrics", StaticFiles(directory=settings.LYRICS_DIR), name="lyrics")

@app.get("/list-songs")
def list_songs():
    result = music_service.list_songs()
    if isinstance(result, dict) and "error" in result:
        return result
    return result

@app.get("/lyrics-embedded/{filename}")
def get_embedded_lyrics(filename: str):
    lyrics = music_service.get_embedded_lyrics(filename)
    if not lyrics:
        raise HTTPException(status_code=404, detail="No embedded lyrics found")
    
    return Response(content=str(lyrics), media_type="text/plain")

@app.get("/cover/{filename}")
def get_cover(filename: str):
    data, mime = music_service.get_cover_data(filename)
    if not data:
        raise HTTPException(status_code=404, detail="No cover found in metadata")
    
    return Response(content=data, media_type=mime)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=9000)
