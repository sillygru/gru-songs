import os
import argparse
from PIL import Image
import numpy as np

EXTENSIONS = (".png", ".jpg", ".jpeg", ".webp")

def auto_crop(img):
    arr = np.array(img.convert("RGB"))
    h, w, _ = arr.shape
    gray = arr.mean(axis=2)
    row_std = gray.std(axis=1)

    # threshold to detect "real content"
    thresh = np.percentile(row_std, 35)

    # find content start (top)
    top = 0
    for i in range(h):
        if row_std[i] > thresh:
            top = i
            break

    # find content end (bottom)
    bottom = h
    for i in range(h - 1, -1, -1):
        if row_std[i] > thresh:
            bottom = i + 1
            break

    # safety clamps (avoid tiny/no crop)
    top = max(top, int(h * 0.04))
    bottom = min(bottom, h - int(h * 0.04))

    return img.crop((0, top, w, bottom)), top, h - bottom


def manual_crop(img, top_px, bottom_px):
    w, h = img.size
    return img.crop((0, top_px, w, h - bottom_px))


def process_folder(folder, manual_top=None, manual_bottom=None):
    for file in os.listdir(folder):
        if not file.lower().endswith(EXTENSIONS):
            continue

        path = os.path.join(folder, file)
        img = Image.open(path)

        if manual_top is not None or manual_bottom is not None:
            top = manual_top or 0
            bottom = manual_bottom or 0
            cropped = manual_crop(img, top, bottom)
            print(f"{file}: manual crop top={top}, bottom={bottom}")
        else:
            cropped, top, bottom = auto_crop(img)
            print(f"{file}: auto crop top={top}, bottom={bottom}")

        # overwrite original
        cropped.save(path, quality=95)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Crop status and navigation bars from screenshots")
    parser.add_argument("folder", help="Path to folder with images")
    parser.add_argument("--top", type=int, help="Manual pixels to remove from top")
    parser.add_argument("--bottom", type=int, help="Manual pixels to remove from bottom")

    args = parser.parse_args()

    process_folder(
        args.folder,
        manual_top=args.top,
        manual_bottom=args.bottom
    )

