#!/usr/bin/env python3
"""Enemy model sheet from build/enemies/<Key>.json (tools/enemy_sheet.luau): for every model
FRONT, 3/4, SIDE and the GAME view (the run camera, the enemy facing you), side by side.

usage: python3 tools/enemy_sheet.py [Key ...]   ->  build/enemies/sheet.png
"""

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_sheet  # noqa: E402  (camera + renderer helpers)
from PIL import Image  # noqa: E402

SRC = "build/enemies"


def row(key):
    data = json.load(open(os.path.join(SRC, key + ".json")))
    parts = data["parts"]
    top = max(3.0, data["top"])
    W, H = 260, 300
    target = (0, top * 0.5, 0)
    dist = top * 2.6 + 6
    panels = []
    for name, angle, lift in (("FRONT", 0, 0.3), ("3/4", -38, 0.6), ("SIDE", 90, 0.3)):
        a = math.radians(angle)
        eye = (math.sin(a) * dist, target[1] + dist * lift, -math.cos(a) * dist)
        panels.append((name, hero_sheet.view(parts, (W, H), eye, target, 30)))
    pitch = math.radians(56)
    eye = (0.0, math.sin(pitch) * 64, -math.cos(pitch) * 64)
    big = hero_sheet.view(parts, (W * 3, H * 3), eye, (0, top * 0.4, 0), 55 / 3.2, ground=True)
    panels.append(("GAME (facing you)", big.resize((W, H), Image.LANCZOS)))
    out = Image.new("RGBA", (W * len(panels), H), (20, 18, 30, 255))
    for i, (name, img) in enumerate(panels):
        out.alpha_composite(hero_sheet.label(img, key + "  " + name), (i * W, 0))
    return out


if __name__ == "__main__":
    keys = sys.argv[1:] or ["BigQuack", "Duckling", "Cartzilla", "JackpotJimmy", "CoinStack", "Six", "Seven", "TickTock"]
    rows = [row(k) for k in keys]
    sheet = Image.new("RGB", (rows[0].width, sum(r.height for r in rows)), (20, 18, 30))
    y = 0
    for r in rows:
        sheet.paste(r.convert("RGB"), (0, y))
        y += r.height
    path = os.path.join(SRC, "sheet.png")
    sheet.save(path)
    print(path)
