#!/usr/bin/env python3
"""Draws the app icon (a rounded square with a hand-raised question mark style person) and writes AppIcon.icns."""
import os, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont

out = sys.argv[1]
S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
# gradient square
grad = Image.new("RGB", (S, S))
px = grad.load()
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * S)
        px[x, y] = (int(40 + 30 * t), int(90 + 70 * t), int(235 - 30 * t))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle((60, 60, S - 60, S - 60), radius=210, fill=255)
img.paste(grad, (0, 0), mask)
d = ImageDraw.Draw(img)
# a person: head and shoulders, white
d.ellipse((372, 250, 652, 530), fill=(255, 255, 255, 255))
d.pieslice((232, 560, 792, 1120), 180, 360, fill=(255, 255, 255, 255))
# a small question mark badge
d.ellipse((600, 520, 860, 780), fill=(255, 204, 0, 255))
for path in ["/System/Library/Fonts/Helvetica.ttc", "/System/Library/Fonts/SFNS.ttf"]:
    if os.path.exists(path):
        font = ImageFont.truetype(path, 210); break
else:
    font = ImageFont.load_default()
d.text((730, 650), "?", font=font, fill=(40, 40, 40, 255), anchor="mm")

with tempfile.TemporaryDirectory() as t:
    iconset = os.path.join(t, "AppIcon.iconset"); os.makedirs(iconset)
    for size in (16, 32, 64, 128, 256, 512, 1024):
        img.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, f"icon_{size}x{size}.png"))
    for size in (16, 32, 128, 256, 512):
        img.resize((size * 2, size * 2), Image.LANCZOS).save(os.path.join(iconset, f"icon_{size}x{size}@2x.png"))
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out], check=True)
print("wrote", out)
