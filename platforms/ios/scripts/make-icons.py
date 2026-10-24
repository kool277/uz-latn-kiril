#!/usr/bin/env python3
"""Draws the app icons (a white Ö on a blue-green gradient) into the asset catalogs:
Resources/iOSApp/Assets.xcassets/AppIcon.appiconset (one 1024 px opaque PNG) and
Resources/MacApp/Assets.xcassets/AppIcon.appiconset (16…1024 px, rounded square with a shadow).
usage: python3 platforms/ios/scripts/make-icons.py   (needs Pillow; the PNGs are committed, so only to redraw them)"""
import os

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(os.path.dirname(HERE), 'Resources')
TOP, BOTTOM = (10, 110, 189), (18, 163, 127)  # #0A6EBD → #12A37F
SS = 4  # supersampling


def gradient(size):
    img = Image.new('RGB', (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM))
    return img


def glyph_mask(size, scale=1.0):
    """Ö: an elliptic ring and two dots, in a 1024-unit design space scaled to `size`."""
    m = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(m)
    k = size / 1024

    def p(v, centre=512):
        return (centre + (v - centre) * scale) * k

    cx, cy, rx, ry, w = 512, 588, 250, 270, 94
    d.ellipse([p(cx - rx), p(cy - ry), p(cx + rx), p(cy + ry)], fill=255)
    d.ellipse([p(cx - rx + w), p(cy - ry + w), p(cx + rx - w), p(cy + ry - w)], fill=0)
    for dx in (-104, 104):
        r = 60
        d.ellipse([p(cx + dx - r), p(232 - r), p(cx + dx + r), p(232 + r)], fill=255)
    return m


def ios_icon():
    big = 1024 * SS
    img = gradient(256).resize((big, big), Image.BICUBIC)
    img.paste((255, 255, 255), (0, 0), glyph_mask(big))
    return img.resize((1024, 1024), Image.LANCZOS)  # opaque RGB: the App Store rejects alpha


def mac_icon(size):
    big = 1024 * SS
    canvas = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    inset, radius = 100 * SS, 185 * SS
    shape = Image.new('L', (big, big), 0)
    ImageDraw.Draw(shape).rounded_rectangle([inset, inset, big - inset, big - inset], radius, fill=255)
    shadow = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    shadow.putalpha(shape.point(lambda a: a * 0.35).filter(ImageFilter.GaussianBlur(14 * SS)))
    canvas.alpha_composite(shadow, (0, 12 * SS))
    face = gradient(256).resize((big, big), Image.BICUBIC).convert('RGBA')
    face.putalpha(shape)
    canvas.alpha_composite(face)
    white = Image.new('RGBA', (big, big), (255, 255, 255, 255))
    white.putalpha(glyph_mask(big, scale=0.8))
    canvas.alpha_composite(white)
    return canvas.resize((size, size), Image.LANCZOS)


def main():
    ios = os.path.join(RES, 'iOSApp', 'Assets.xcassets', 'AppIcon.appiconset')
    mac = os.path.join(RES, 'MacApp', 'Assets.xcassets', 'AppIcon.appiconset')
    os.makedirs(ios, exist_ok=True)
    os.makedirs(mac, exist_ok=True)
    ios_icon().save(os.path.join(ios, 'AppIcon-1024.png'), optimize=True)
    master = mac_icon(1024)
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = 'icon_%dx%d%s.png' % (pt, pt, '@2x' if scale == 2 else '')
            (master if px == 1024 else master.resize((px, px), Image.LANCZOS)).save(os.path.join(mac, name), optimize=True)
    print('icons written')


if __name__ == '__main__':
    main()
