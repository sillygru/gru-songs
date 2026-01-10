import os
import shutil
import subprocess
import sys

# Configuration
SOURCE_DIR = "Songs"
BACKUP_DIR = "old"
FFMPEG_ARGS = ["-c:a", "aac", "-b:a", "320k", "-map_metadata", "0", "-c:v", "copy", "-y"]

def run_compression():
    # 1. Setup Directories
    base_path = os.path.dirname(os.path.abspath(__file__))
    songs_path = os.path.join(base_path, SOURCE_DIR)
    backup_path = os.path.join(base_path, BACKUP_DIR)

    if not os.path.exists(songs_path):
        print(f"❌ Error: Could not find '{SOURCE_DIR}' directory.")
        return

    if not os.path.exists(backup_path):
        os.makedirs(backup_path)
        print(f"📁 Created backup directory: {backup_path}")

    # 2. Get list of files (M4A ONLY)
    files = sorted([f for f in os.listdir(songs_path) if f.lower().endswith('.m4a')])
    total_files = len(files)
    
    print(f"🎵 Found {total_files} .m4a files in {SOURCE_DIR}/")
    print(f"⚠️  Starting compression to 320kbps AAC...")
    print("-" * 50)

    for index, filename in enumerate(files):
        original_file_path = os.path.join(songs_path, filename)
        backup_file_path = os.path.join(backup_path, filename)
        
        # Friendly progress indicator
        print(f"[{index + 1}/{total_files}] Processing: {filename}...", end=" ", flush=True)

        try:
            # Step A: Ensure we have a backup source
            # If the script was interrupted previously, the file might only exist in 'old/'
            if os.path.exists(backup_file_path):
                # Good, we have a safe backup. Use it as input.
                input_source = backup_file_path
            else:
                # Move current file to backup
                shutil.move(original_file_path, backup_file_path)
                input_source = backup_file_path

            # Step B: Compress
            cmd = [
                "ffmpeg", 
                "-i", input_source,     # Input from backup
            ] + FFMPEG_ARGS + [
                original_file_path      # Output to Songs/
            ]

            # Run FFmpeg (Capture output so we don't see scary errors unless it fails)
            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode != 0:
                print("❌ Failed!")
                print(f"    Reason: FFmpeg could not process this file. Restoring original.")
                # Restore the original file
                if os.path.exists(original_file_path):
                    os.remove(original_file_path) # Remove partial/corrupt output
                shutil.copy2(backup_file_path, original_file_path)
            else:
                # Calculate space savings
                old_size = os.path.getsize(backup_file_path) / (1024 * 1024)
                new_size = os.path.getsize(original_file_path) / (1024 * 1024)
                saved = old_size - new_size
                print(f"✅ (Saved {saved:.2f}MB)")

        except KeyboardInterrupt:
            print("\n\n⚠️  Script cancelled by user.")
            print("   The current file might be missing from 'Songs/'.")
            print(f"   Check '{backup_path}' to restore it manually if needed.")
            sys.exit(0)
        except Exception as e:
            print(f"\n   ❌ Critical Error: {e}")
            # Attempt restore
            if os.path.exists(backup_file_path) and not os.path.exists(original_file_path):
                shutil.copy2(backup_file_path, original_file_path)

    print("-" * 50)
    print("🎉 Compression complete.")
    print("👉 You can now clear your app cache and restart the server.")

if __name__ == "__main__":
    run_compression()