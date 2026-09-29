#!/usr/bin/env python3
"""Hero turnaround sheets from build/heroes/<Key>.json (tools/hero_sheet.luau).

For every hero: FRONT, 3/4, SIDE, BACK 3/4, TOP (straight down), GAME (the run camera: 56 deg
from above, far away, like in a real run, from behind and from the front) and SMALL (the game
view at the size the hero has on a phone), so silhouette, proportions and readability can be
judged at a glance. Also a LINEUP of the given heroes side by side (front + game view).

usage: python3 tools/hero_sheet.py [Key ...]   ->  build/heroes/<Key>.png, build/heroes/lineup.png
"""

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render3d  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

SRC = "build/heroes"
BG_TOP, BG_BOTTOM = (58, 52, 92), (26, 24, 40)
GROUND = (96, 150, 104)


def look_at(eye, target, fov):
    """a Roblox camera CFrame {p, r, fov} looking from eye to target (LookVector = -Z)"""
    lx, ly, lz = (target[0] - eye[0], target[1] - eye[1], target[2] - eye[2])
    n = math.sqrt(lx * lx + ly * ly + lz * lz)
    look = (lx / n, ly / n, lz / n)
    up = (0.0, 1.0, 0.0) if abs(look[1]) < 0.99 else (0.0, 0.0, -1.0)  # straight down: front (-Z) is up
    rx, ry, rz = look[1] * up[2] - look[2] * up[1], look[2] * up[0] - look[0] * up[2], look[0] * up[1] - look[1] * up[0]
    rn = math.sqrt(rx * rx + ry * ry + rz * rz) or 1.0
    right = (rx / rn, ry / rn, rz / rn)
    u = (right[1] * look[2] - right[2] * look[1], right[2] * look[0] - right[0] * look[2], right[0] * look[1] - right[1] * look[0])
    back = (-look[0], -look[1], -look[2])
    # row-major 3x3 with columns right, up, back
    r = [right[0], u[0], back[0], right[1], u[1], back[1], right[2], u[2], back[2]]
    return {"p": list(eye), "r": r, "fov": fov}


def background(size, ground=False):
    w, h = size
    img = Image.new("RGBA", size)
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        c = tuple(int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3))
        d.line([(0, y), (w, y)], fill=c + (255,))
    if ground:
        d.rectangle([0, 0, w, h], fill=GROUND + (255,))
    return img


LIGHT = render3d.Light(direction=(-0.45, -0.8, -0.35), ambient=(0.66, 0.66, 0.74), color=(1, 0.97, 0.92))


FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def surface_text(img, parts, cam, eye):
    """the SurfaceGui text of a part (THE 67's screen) on its front face, when that face is seen"""
    c = render3d.Camera(cam, img.size[0], img.size[1])
    d = ImageDraw.Draw(img)
    for part in parts:
        text = part.get("text")
        if not text:
            continue
        p, r, s = part["p"], part["r"], part["s"]
        centre = render3d._xf(p, r, (0, 0, -s[2] / 2))
        normal = render3d._rot(r, (0, 0, -1))
        if sum(normal[i] * (eye[i] - centre[i]) for i in range(3)) <= 0:
            continue
        pts = []
        for u, v in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            vv = c.view(render3d._xf(p, r, (u * s[0] / 2, v * s[1] / 2, -s[2] / 2)))
            if vv[2] <= 0.1:
                break
            pts.append(c.screen(vv))
        if len(pts) < 4:
            continue
        xs, ys = [q[0] for q in pts], [q[1] for q in pts]
        w, h = max(xs) - min(xs), max(ys) - min(ys)
        if w < 4 or h < 4:
            continue
        size = max(6, int(min(h * 0.8, w * 0.8 / max(1, len(text["value"])) * 1.6)))
        font = ImageFont.truetype(FONT, size) if os.path.exists(FONT) else ImageFont.load_default()
        col = tuple(int(v * 255) for v in text["c"]) + (255,)
        d.text(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2), text["value"], fill=col, font=font, anchor="mm")


def view(parts, size, eye, target, fov, ground=False, shadow=True):
    img = background(size, ground)
    cam = look_at(eye, target, fov)
    if shadow:
        c = render3d.Camera(cam, size[0], size[1])
        render3d.shadows(img, c, [[[0, -3, 0], 1.9]])
    layer = render3d.render_viewport(size, cam, parts, LIGHT)
    surface_text(layer, parts, cam, eye)
    img.alpha_composite(layer)
    return img


def label(img, text):
    d = ImageDraw.Draw(img)
    d.text((10, 8), text, fill=(235, 232, 250, 255))
    return img


def orbit(angle_deg, dist, height, target=(0, -0.7, 0)):
    a = math.radians(angle_deg)
    # angle 0 = in front of the hero (the hero faces -Z)
    return (math.sin(a) * dist, target[1] + height, -math.cos(a) * dist)


def game_eye(from_front, zoom=64):
    pitch = math.radians(56)
    z = math.cos(pitch) * zoom
    return (0.0, math.sin(pitch) * zoom - 1.5, -z if from_front else z)


def sheet(key):
    data = json.load(open(os.path.join(SRC, key + ".json")))
    parts = data["parts"]
    W, H = 300, 380
    target = (0, -0.65, 0)
    panels = [
        ("FRONT", view(parts, (W, H), orbit(0, 15, 0.4, target), target, 26)),
        ("3/4", view(parts, (W, H), orbit(-38, 15, 1.2, target), target, 26)),
        ("SIDE", view(parts, (W, H), orbit(90, 15, 0.4, target), target, 26)),
        ("BACK 3/4", view(parts, (W, H), orbit(150, 15, 1.2, target), target, 26)),
        ("TOP (front = up)", view(parts, (W, H), (0.0, 16.0, 0.6), (0, 0, 0), 26)),
    ]
    # the run camera: the hero is ~7% of the screen height; crop around it and scale up
    game = []
    for name, front in (("GAME (behind)", False), ("GAME (front)", True)):
        big = view(parts, (W * 4, H * 4), game_eye(front), (0, -1.5, 0), 55 / 8, ground=True)
        game.append((name, big.resize((W, H), Image.LANCZOS)))
    # SMALL: the hero at phone size (~28 px tall), shown 4x with hard pixels
    tiny = view(parts, (64, 64), game_eye(False), (0, -1.5, 0), 9.4, ground=True)
    small = tiny.resize((W, W), Image.NEAREST)
    small_panel = background((W, H))
    small_panel.alpha_composite(small, (0, (H - W) // 2))
    panels += game + [("SMALL (phone, x4)", small_panel)]
    out = Image.new("RGBA", (W * 4, H * 2), (20, 18, 30, 255))
    for i, (name, img) in enumerate(panels):
        out.alpha_composite(label(img, name), ((i % 4) * W, (i // 4) * H))
    d = ImageDraw.Draw(out)
    d.text((W * 4 - 220, H * 2 - 22), "%s  %d pieces" % (key, data["count"]), fill=(255, 214, 90, 255))
    path = os.path.join(SRC, key + ".png")
    out.convert("RGB").save(path)
    return path, parts


def lineup(keys):
    W, H = 260, 340
    row1 = Image.new("RGBA", (W * len(keys), H), (20, 18, 30, 255))
    row2 = Image.new("RGBA", (W * len(keys), H), (20, 18, 30, 255))
    target = (0, -0.65, 0)
    for i, key in enumerate(keys):
        parts = json.load(open(os.path.join(SRC, key + ".json")))["parts"]
        row1.alpha_composite(label(view(parts, (W, H), orbit(-25, 15, 0.9, target), target, 27), key), (i * W, 0))
        big = view(parts, (W * 3, H * 3), game_eye(False), (0, -1.5, 0), 55 / 5, ground=True)
        row2.alpha_composite(label(big.resize((W, H), Image.LANCZOS), key + " (game)"), (i * W, 0))
    out = Image.new("RGBA", (W * len(keys), H * 2))
    out.alpha_composite(row1, (0, 0))
    out.alpha_composite(row2, (0, H))
    path = os.path.join(SRC, "lineup.png")
    out.convert("RGB").save(path)
    return path


if __name__ == "__main__":
    keys = sys.argv[1:] or sorted(f[:-5] for f in os.listdir(SRC) if f.endswith(".json"))
    for k in keys:
        print(sheet(k)[0])
    print(lineup(keys))
