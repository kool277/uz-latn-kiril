#!/usr/bin/env python3
"""Draws the UzTranslit app icon (a white Ö on a blue-to-teal rounded square) and writes every size the app and the
installers need. Run it after changing the design; the outputs are committed:
  resources/icons/uztranslit-{16,24,32,48,64,128,256,512}.png   window/tray icon (Qt resource), Linux desktop icon
  packaging/windows/uztranslit.ico                                 executable and installer icon
  packaging/macos/uztranslit.icns                                  app bundle icon
usage: python3 packaging/make-icons.py [path/to/Bold.ttf]   (needs Pillow; default font: Noto Sans Bold / DejaVu Sans Bold)"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FONTS = [
    "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]
TOP, BOTTOM = (0x15, 0x65, 0xC0), (0x00, 0x89, 0x7B)


def master(size, font_path):
    scale = 4  # draw large, then downsample: smooth edges
    s = size * scale
    gradient = Image.new("RGBA", (s, s))
    px = gradient.load()
    for y in range(s):
        t = y / (s - 1)
        c = tuple(round(TOP[k] + (BOTTOM[k] - TOP[k]) * t) for k in range(3)) + (255,)
        for x in range(s):
            px[x, y] = c
    mask = Image.new("L", (s, s), 0)
    inset = round(s * 0.04)
    ImageDraw.Draw(mask).rounded_rectangle((inset, inset, s - inset - 1, s - inset - 1), radius=round(s * 0.22), fill=255)
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    img.paste(gradient, (0, 0), mask)
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(font_path, round(s * 0.64))
    text = "Ö"
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    x = (s - (right - left)) / 2 - left
    y = (s - (bottom - top)) / 2 - top + s * 0.02
    draw.text((x, y), text, font=font, fill=(255, 255, 255, 255))
    return img.resize((size, size), Image.LANCZOS)


def main():
    font_path = sys.argv[1] if len(sys.argv) > 1 else next((f for f in FONTS if os.path.exists(f)), None)
    if not font_path:
        sys.exit("no bold font found; pass the path of a .ttf file")
    big = master(1024, font_path)
    icons = os.path.join(ROOT, "resources", "icons")
    os.makedirs(icons, exist_ok=True)
    for size in (16, 24, 32, 48, 64, 128, 256, 512):
        img = big.resize((size, size), Image.LANCZOS) if size >= 64 else master(size, font_path)
        img.save(os.path.join(icons, "uztranslit-%d.png" % size), optimize=True)
    os.makedirs(os.path.join(HERE, "windows"), exist_ok=True)
    big.save(os.path.join(HERE, "windows", "uztranslit.ico"),
             sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    os.makedirs(os.path.join(HERE, "macos"), exist_ok=True)
    big.save(os.path.join(HERE, "macos", "uztranslit.icns"))
    print("icons written to", icons, "and packaging/{windows,macos}")


if __name__ == "__main__":
    main()
