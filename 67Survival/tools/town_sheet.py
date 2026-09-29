#!/usr/bin/env python3
"""67 TOWN review, part 2: draws build/town/town.json (tools/town_sheet.luau) from the RUN camera
(CameraController: pitch 56, zoom 64, FOV 55, north up), plus an overview and a plan.

  square, gardens, maze, duck, lot, checkout, backrooms, strip, jackpot, alley, rift, altars,
  obelisk, gate, vault, relics
             the run camera over that spot (a hero stands there for scale)
  overview   high up from the south
  plan       straight down (north = up)

usage: python3 tools/town_sheet.py [view ...]   ->  build/town/<view>.png, build/town/sheet.png
"""

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import map_sheet  # noqa: E402  (the renderer of 67 LAND: layering, signs, labels)
from PIL import Image  # noqa: E402

SRC = "build/town/town.json"
OUT = "build/town"
W, H = map_sheet.W, map_sheet.H

# flat things on the ground, drawn first from low to high (the painter's sort would otherwise
# let huge ground faces cover what stands on them)
map_sheet.GROUND = {
    "Tile", "Plaza", "PlazaRing", "PlazaInner", "Avenue", "GardenPath", "PathCircle", "LairRing", "LairFloor",
    "VaultRing", "VaultPad", "Boulevard", "BoulevardEdge", "BoulevardDash", "StripStreet", "BackAlley", "RiftPath",
    "Crack", "StallRow", "StallLine", "Reserved67", "Spot67", "PondRim", "Pond", "LairPond", "VoidRim", "VoidPool",
    "FlowerBed", "Blanket", "BlanketStripe", "SpeedBump", "LilyPad", "BackroomsFloor", "GazeboFloor", "Ring",
}
map_sheet.BELOW = set()

PITCH = math.radians(56)
ZOOM = 64


def run_cam(x, z, zoom=ZOOM):
    focus = (x, 3.0, z)
    eye = (x, 3.0 + math.sin(PITCH) * zoom, z + math.cos(PITCH) * zoom)
    return map_sheet.look_at(eye, (x, 4.5, z), 55)


SPOTS = {
    "square": (0, 20),
    "gardens": (-150, 20),
    "maze": (-190, -30),
    "duck": (-170, 140),
    "lot": (40, 150),
    "checkout": (165, 160),
    "backrooms": (40, 214),
    "strip": (165, -30),
    "jackpot": (160, -155),
    "alley": (105, -100),
    "rift": (-40, -150),
    "altars": (-80, -165),
    "obelisk": (-170, -140),
    "gate": (0, -70),
    "vault": (210, 205),
    "relics": (0, 40),
}


# the mini-bosses up close (the run camera zoomed in); where they really stand wins
CLOSE = {
    "quack": (-165, 150),
    "cartzilla": (168, 162),
    "jimmy": (160, -160),
    "twins": (-90, -179),
    "ticktock": (-40, 176),
}
CLOSE_KEY = {"quack": "BigQuack", "cartzilla": "Cartzilla", "jimmy": "JackpotJimmy", "ticktock": "TickTock"}


def views(data=None):
    minis = (data or {}).get("minis") or {}
    out = {}
    for name, (x, z) in SPOTS.items():
        out[name] = (run_cam(x, z), (x, 3.0, z + 6))
    for name, (x, z) in CLOSE.items():
        at = minis.get(CLOSE_KEY.get(name, ""))
        if at:
            x, z = at
        out[name] = (run_cam(x, z + 2, 26), None)
    out["overview"] = (map_sheet.look_at((0, 330, 420), (0, 0, 10), 50), None)
    out["plan"] = (map_sheet.look_at((0, 900, 0.5), (0, 0, 0), 32), None)
    return out


def main():
    data = json.load(open(SRC))
    want = sys.argv[1:]
    all_views = views(data)
    names = want or list(all_views.keys())
    done = []
    for name in names:
        cam, root = all_views[name]
        img = map_sheet.render(data, cam, root)
        map_sheet.label(img, name.upper())
        path = os.path.join(OUT, name + ".png")
        img.convert("RGB").save(path)
        done.append((name, img))
        print(path)
    if len(done) > 1:
        tw, th = W // 2, H // 2
        cols = 2
        rows = (len(done) + cols - 1) // cols
        sheet = Image.new("RGB", (tw * cols, th * rows), (20, 16, 30))
        for i, (_, img) in enumerate(done):
            sheet.paste(img.convert("RGB").resize((tw, th), Image.LANCZOS), ((i % cols) * tw, (i // cols) * th))
        sheet.save(os.path.join(OUT, "sheet.png"))
        print(os.path.join(OUT, "sheet.png"))


if __name__ == "__main__":
    main()
