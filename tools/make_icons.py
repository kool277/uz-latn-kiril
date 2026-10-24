#!/usr/bin/env python3
"""Renders the command icons of the Office ribbon and the LibreOffice toolbar (the web app's style: a teal tile with a
white letter). The PNGs and SVGs are committed; run this again only when the design changes. Needs Pillow and the
DejaVu fonts.

    python3 tools/make_icons.py
      -> office-vba/ribbon/images/<name>.png                  32 px (the ribbon scales it to 16 px for small buttons)
      -> libreoffice/extension/icons/<name>_16.png, _26.png    LibreOffice small / large toolbar icons
      -> libreoffice/extension/icons/<name>.svg
      -> platforms/office-addin/assets/icon-<size>.png        the Office add-in (16, 32, 64, 80, 128 px)
"""
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEAL, WHITE = (15, 118, 110, 255), (255, 255, 255, 255)
SERIF = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
# name: (glyph, font, relative glyph size)
ICONS = {
    "to_new": ("Ö", SERIF, 0.62),            # Ö: Yangi lotin
    "to_lat": ("Oʻ", SERIF, 0.50),           # Oʻ: Lotin 1995
    "to_cyr": ("Ў", SERIF, 0.62),            # Ў: Кирилл
    "self_test": ("✓", SANS, 0.78),          # ✓
}


def png(glyph, font_path, rel, size, path):
    scale = 8                                     # draw large, then downsample: smooth edges at 16 px
    big = size * scale
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, big - 1, big - 1), radius=int(big * 0.2), fill=TEAL)
    font = ImageFont.truetype(font_path, int(big * rel))
    l, t, r, b = d.textbbox((0, 0), glyph, font=font)
    d.text(((big - (r - l)) / 2 - l, (big - (b - t)) / 2 - t), glyph, font=font, fill=WHITE)
    img.resize((size, size), Image.LANCZOS).save(path, optimize=True)


def svg(glyph, rel, path):
    family = "DejaVu Sans, sans-serif" if glyph == "✓" else "DejaVu Serif, Georgia, serif"
    text = "".join("&#x%X;" % ord(c) if ord(c) > 127 else c for c in glyph)
    with open(path, "w", encoding="ascii") as f:
        f.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 26 26" width="26" height="26">'
                '<rect width="26" height="26" rx="5.2" fill="#0f766e"/>'
                '<text x="13" y="13" dy="0.36em" text-anchor="middle" font-family="%s" font-weight="700" '
                'font-size="%.1f" fill="#fff">%s</text></svg>\n' % (family, 26 * rel, text))


def main():
    ribbon = os.path.join(ROOT, "office-vba", "ribbon", "images")
    lo = os.path.join(ROOT, "libreoffice", "extension", "icons")
    os.makedirs(ribbon, exist_ok=True)
    os.makedirs(lo, exist_ok=True)
    for name, (glyph, font, rel) in ICONS.items():
        png(glyph, font, rel, 32, os.path.join(ribbon, name + ".png"))
        for size in (16, 26):
            png(glyph, font, rel, size, os.path.join(lo, "%s_%d.png" % (name, size)))
        svg(glyph, rel, os.path.join(lo, name + ".svg"))
    addin = os.path.join(ROOT, "platforms", "office-addin", "assets")
    os.makedirs(addin, exist_ok=True)
    glyph, font, rel = ICONS["to_new"]
    for size in (16, 32, 64, 80, 128):
        png(glyph, font, rel, size, os.path.join(addin, "icon-%d.png" % size))
    print("icons:", ", ".join(ICONS), "->", os.path.relpath(ribbon, ROOT), "and", os.path.relpath(lo, ROOT))


if __name__ == "__main__":
    main()
