#!/usr/bin/env python3
"""Lays out tools/asset_shot.gd's tiles as one contact sheet with each id under its picture.
Run: python3 tools/assets/sheet.py TILE_DIR out.png [columns]"""
import os, sys
from PIL import Image, ImageDraw


def main():
    src, out = sys.argv[1], sys.argv[2]
    cols = int(sys.argv[3]) if len(sys.argv) > 3 else 6
    files = sorted(f for f in os.listdir(src) if f.endswith(".png"))
    tile = Image.open(os.path.join(src, files[0])).size[0] if files else 400
    rows = (len(files) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tile, rows * (tile + 28)), "white")
    d = ImageDraw.Draw(sheet)
    for i, f in enumerate(files):
        x, y = (i % cols) * tile, (i // cols) * (tile + 28)
        sheet.paste(Image.open(os.path.join(src, f)).convert("RGB"), (x, y))
        d.text((x + 6, y + tile + 6), f[:-4], fill="black")
    sheet.save(out)


if __name__ == "__main__":
    main()
