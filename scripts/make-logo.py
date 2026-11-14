#!/usr/bin/env python3
"""Builds the humanpls logo set from one geometry (everything below is in a 1000 x 1000 canvas).

  design/logo/humanpls-mark.svg / .png            color mark, transparent background
  design/logo/humanpls-mark-on-dark.svg / .png    for dark backgrounds
  design/logo/humanpls-mark-mono.svg              one color, no sparks (the menu bar icon is made from this)
  design/logo/humanpls-app-icon.svg / .png        macOS app icon, 1024 x 1024
  design/logo/AppIcon.icns                        used by scripts/build-app.sh
  Sources/humanpls/Assets.swift                   the menu bar icon as a PNG inside the binary

Needs rsvg-convert (brew install librsvg) and iconutil.
"""
import base64, os, pathlib, subprocess, sys, tempfile

root = pathlib.Path(__file__).resolve().parent.parent
out = root / "design" / "logo"
out.mkdir(parents=True, exist_ok=True)

INK, WHITE, CORAL, CREAM = "#111110", "#FFFFFF", "#FE614F", "#FFF3E6"

# --- geometry -------------------------------------------------------------------------------
BX, BY, BW, BH, BR = 100, 210, 700, 756, 104           # the dome-shaped body: x, y, width, height, bottom corner radius
BODY = (f"M{BX},{BY + BW/2} A{BW/2},{BW/2} 0 0 1 {BX + BW},{BY + BW/2} V{BY + BH - BR} "
        f"A{BR},{BR} 0 0 1 {BX + BW - BR},{BY + BH} H{BX + BR} A{BR},{BR} 0 0 1 {BX},{BY + BH - BR} Z")
STEM = dict(x=260, y=337, width=155, height=513, rx=77.5)                    # the stem of the h
BLOB = "M400,501 H529 A135,135 0 0 1 664,636 V770 A80,80 0 0 1 584,850 H460 A60,60 0 0 1 400,790 Z"   # shoulder and leg
EYES = [dict(x=413, y=641, width=68, height=97, rx=34), dict(x=526, y=641, width=68, height=97, rx=34)]
SPARKS = [(558, 135, 103, 0), (666, 149, 120, 33), (744, 229, 111, 63)]      # center x, y, length, rotation in degrees
SPARK_W = 55

def rect(r, fill, extra=""):
    return f'<rect x="{r["x"]}" y="{r["y"]}" width="{r["width"]}" height="{r["height"]}" rx="{r["rx"]}" fill="{fill}"{extra}/>'

def sparks(fill):
    s = ""
    for cx, cy, ln, rot in SPARKS:
        s += (f'<rect x="{cx - SPARK_W/2}" y="{cy - ln/2}" width="{SPARK_W}" height="{ln}" rx="{SPARK_W/2}" fill="{fill}" '
              f'transform="rotate({rot} {cx} {cy})"/>')
    return s

def mark(body, h, eyes, spark):
    return (f'{sparks(spark)}<path d="{BODY}" fill="{body}"/>{rect(STEM, h)}<path d="{BLOB}" fill="{h}"/>'
            + "".join(rect(e, eyes) for e in EYES))

def svg(inner, box="0 0 1000 1000", bg=""):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{box}" width="1000" height="1000">{bg}{inner}</svg>\n'

def write(name, text): (out / name).write_text(text, encoding="utf-8")

def png(svg_name, png_name, size):
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(out / svg_name), "-o", str(out / png_name)], check=True)

# --- color mark -----------------------------------------------------------------------------
write("humanpls-mark.svg", svg(mark(INK, WHITE, INK, CORAL)))
png("humanpls-mark.svg", "humanpls-mark.png", 1024)
# --- on dark: the body turns light, the h turns dark -----------------------------------------
write("humanpls-mark-on-dark.svg", svg(mark("#F5F5F4", INK, "#F5F5F4", CORAL), bg='<rect width="1000" height="1000" fill="#111110"/>'))
png("humanpls-mark-on-dark.svg", "humanpls-mark-on-dark.png", 1024)

# --- one color: body with the h cut out, eyes are body again, no sparks -----------------------
mono_inner = (f'<mask id="m"><rect width="1000" height="1000" fill="#fff"/>{rect(STEM, "#000")}<path d="{BLOB}" fill="#000"/>'
              + "".join(rect(e, "#fff") for e in EYES) + f'</mask><path d="{BODY}" fill="#000" mask="url(#m)"/>')
write("humanpls-mark-mono.svg", svg(mono_inner, box=f"{BX} {BY} {BW} {BH}"))

# --- app icon: macOS rounded square (824 of 1024), cream, with the mark ----------------------
icon_inner = (f'<rect x="100" y="100" width="824" height="824" rx="186" fill="{CREAM}"/>'
              f'<g transform="translate(224 174) scale(0.64)">{mark(INK, WHITE, INK, CORAL)}</g>')
write("humanpls-app-icon.svg", svg(icon_inner, box="0 0 1024 1024"))
png("humanpls-app-icon.svg", "humanpls-app-icon.png", 1024)

with tempfile.TemporaryDirectory() as t:
    iconset = pathlib.Path(t) / "AppIcon.iconset"; iconset.mkdir()
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = size * scale
            name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
            subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), str(out / "humanpls-app-icon.svg"), "-o", str(iconset / name)], check=True)
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(out / "AppIcon.icns")], check=True)

# --- menu bar icon: a template image (black + transparency), 72 px tall, inside the binary ----
with tempfile.TemporaryDirectory() as t:
    p = pathlib.Path(t) / "menubar.png"
    subprocess.run(["rsvg-convert", "-h", "72", str(out / "humanpls-mark-mono.svg"), "-o", str(p)], check=True)
    b64 = base64.b64encode(p.read_bytes()).decode()
(root / "Sources/humanpls/Assets.swift").write_text(
    "// Generated by scripts/make-logo.py. Do not edit.\n\nenum Assets {\n"
    "    /// The menu bar icon: black with transparency, used as a template image. Its shape is 700 x 756.\n"
    f'    static let menuBarPNG = "{b64}"\n    static let menuBarAspect = 700.0 / 756.0\n}}\n', encoding="utf-8")
print("wrote", out)
