import os
import sys

def update_version():
    try:
        old_version = input("Enter old version (e.g., 6.2.0): ").strip()
        new_version = input("Enter new version (e.g., 6.2.1): ").strip()
    except EOFError:
        print("\nNo input received. Exiting.")
        return

    if not old_version or not new_version:
        print("Error: Both old and new versions must be provided.")
        return

    print(f"Updating version from {old_version} to {new_version}...")

    old_comma = old_version.replace('.', ',')
    new_comma = new_version.replace('.', ',')

    exclude_dirs = {'.git', '.dart_tool', 'build', 'ios/Pods', 'macos/Pods', '.pytest_cache', '__pycache__', '.gradle', 'backups', 'users', 'ephemeral'}
    exclude_files = {'pubspec.lock', 'update_version.py', '.metadata', 'pubspec.yaml'}

    updated_count = 0

    for root, dirs, files in os.walk('.'):
        # Skip excluded directories
        dirs[:] = [d for d in dirs if d not in exclude_dirs]

        for file in files:
            if file in exclude_files:
                continue

            file_path = os.path.join(root, file)

            try:
                # Read file content
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()

                changed = False
                new_content = content

                # Regular dot-separated version replacement
                if old_version in content:
                    # Specific check for pubspec.yaml to ensure we don't accidentally match other things
                    # although x.x.x is usually unique enough.
                    new_content = new_content.replace(old_version, new_version)
                    changed = True

                # Special case for Windows .rc files (comma-separated)
                if file.endswith('.rc') and old_comma in content:
                    new_content = new_content.replace(old_comma, new_comma)
                    changed = True

                if changed:
                    with open(file_path, 'w', encoding='utf-8') as f:
                        f.write(new_content)
                    print(f"Updated: {file_path}")
                    updated_count += 1

            except Exception as e:
                print(f"Error processing {file_path}: {e}")

    print(f"\nFinished! Updated {updated_count} files.")

if __name__ == "__main__":
    update_version()
