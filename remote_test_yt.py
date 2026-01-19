import asyncio
import os
import subprocess

async def test_dl():
    url = "https://www.youtube.com/watch?v=jNQXAC9IVRw" # Me at the zoo (very short)
    title = "test_zoo"
    filename = f"{title}.m4a"
    output_path = filename
    
    cmd = [
        "yt-dlp",
        "--no-js-runtimes",
        "--js-runtimes", "node",
        "--remote-components", "ejs:github",
        "-f", "ba[ext=m4a]/ba",
        "-x",
        "--audio-format", "m4a",
        "--embed-thumbnail",
        "--embed-metadata",
        "--convert-thumbnails", "jpg",
        "--cookies-from-browser", "firefox",
        "-o", output_path,
        url
    ]
    
    print(f"Running command: {' '.join(cmd)}")
    
    process = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE
    )
    stdout, stderr = await process.communicate()
    
    if process.returncode != 0:
        print(f"FAIL: {stderr.decode()}")
    else:
        print(f"SUCCESS: {stdout.decode()}")
        if os.path.exists(output_path):
            print(f"File exists: {output_path}")
            os.remove(output_path)
        else:
            print("File NOT found even though success reported")

if __name__ == "__main__":
    asyncio.run(test_dl())
