#!/usr/bin/env python3
"""Top-down render of docs/map.json (from tools/export_map.luau) -> docs/map.png.
Draws parts lowest-first with their colours; enemy blockers get a red outline."""
import json, sys
from PIL import Image, ImageDraw

parts = json.load(open("docs/map.json"))
SCALE = 2  # pixels per stud
minx, maxx = min(p["x"] - p["ex"] / 2 for p in parts), max(p["x"] + p["ex"] / 2 for p in parts)
minz, maxz = min(p["z"] - p["ez"] / 2 for p in parts), max(p["z"] + p["ez"] / 2 for p in parts)
W, H = int((maxx - minx) * SCALE) + 20, int((maxz - minz) * SCALE) + 20
img = Image.new("RGB", (W, H), (20, 18, 40))
draw = ImageDraw.Draw(img)
for p in sorted(parts, key=lambda p: p["top"]):
    if p["t"] >= 0.95:
        continue
    x0 = (p["x"] - p["ex"] / 2 - minx) * SCALE + 10
    x1 = (p["x"] + p["ex"] / 2 - minx) * SCALE + 10
    z0 = (p["z"] - p["ez"] / 2 - minz) * SCALE + 10
    z1 = (p["z"] + p["ez"] / 2 - minz) * SCALE + 10
    color = tuple(int(c * 255) for c in (p["r"], p["g"], p["b"]))
    outline = (230, 40, 60) if p["blocker"] else None
    if p["round"]:
        draw.ellipse([x0, z0, x1, z1], fill=color, outline=outline)
    else:
        draw.rectangle([x0, z0, x1, z1], fill=color, outline=outline)
img.save(sys.argv[1] if len(sys.argv) > 1 else "docs/map.png")
print("rendered", W, "x", H)
