#!/usr/bin/env python3
"""67 LAND review, part 2: draws build/map/lobby.json (tools/map_sheet.luau) from the cameras
the game really uses, plus an overview and a plan.

  hub        the hub camera on the spawn stage (your hero on the pedestal)
  camp, departures, plaza, park, yard, rift, summit, gate67, nowhere, bridge
             the EXPLORE camera (CameraController) with the hero standing there
  overview   high up, from the south-east
  plan       straight down (north = up)

Signs (SurfaceGui text) and floating labels (BillboardGuis) are drawn in depth order with the
faces, so a sign behind a wall stays hidden.

usage: python3 tools/map_sheet.py [view ...]   ->  build/map/<view>.png, build/map/sheet.png
"""

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render3d  # noqa: E402
from PIL import Image, ImageDraw, ImageFilter, ImageFont  # noqa: E402

# big round slabs (the island's ground) are drawn as sectors: the painter's sort goes face by
# face, and one huge cap sorted by its far centre would let the rocks below show through
_cylinder = render3d._cylinder_x


def _cylinder_split(length, radius, seg=18):
    if radius < 8:
        return _cylinder(length, radius, seg)
    out = _cylinder(length, radius, 28)[:-2]
    h = length / 2
    rings = max(2, int(radius / 5))
    for sign in (1, -1):
        for k in range(28):
            a0, a1 = 2 * math.pi * k / 28, 2 * math.pi * (k + 1) / 28
            for j in range(rings):
                r0, r1 = radius * j / rings, radius * (j + 1) / rings
                pts = [(sign * h, math.cos(a0) * r0, math.sin(a0) * r0), (sign * h, math.cos(a0) * r1, math.sin(a0) * r1), (sign * h, math.cos(a1) * r1, math.sin(a1) * r1), (sign * h, math.cos(a1) * r0, math.sin(a1) * r0)]
                out.append(((sign, 0, 0), pts if sign > 0 else list(reversed(pts))))
    return out


render3d._cylinder_x = _cylinder_split

BELOW = {"Underside", "CloudSea", "SummitRock", "Islet"}
GROUND = {"Lawn", "CampLawn", "SpawnTerrace", "TerraceRing", "TerraceInner", "StageRug", "PlazaFloor", "PlazaRing", "PlazaInner", "ParkLawn", "YardFloor", "RiftPlateau", "RiftFloor", "SummitFloor", "SummitTrim", "CampGround"}

SRC = "build/map/lobby.json"
OUT = "build/map"
W, H = 1280, 720
FONTS = {
    "bold": "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "mono": "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
}
_font_cache = {}


def font(size, kind="bold"):
    size = max(6, min(200, int(size)))
    key = (kind, size)
    if key not in _font_cache:
        path = FONTS[kind]
        _font_cache[key] = ImageFont.truetype(path, size) if os.path.exists(path) else ImageFont.load_default()
    return _font_cache[key]


def look_at(eye, target, fov):
    lx, ly, lz = (target[0] - eye[0], target[1] - eye[1], target[2] - eye[2])
    n = math.sqrt(lx * lx + ly * ly + lz * lz)
    look = (lx / n, ly / n, lz / n)
    up = (0.0, 1.0, 0.0) if abs(look[1]) < 0.99 else (0.0, 0.0, 1.0)
    rx, ry, rz = look[1] * up[2] - look[2] * up[1], look[2] * up[0] - look[0] * up[2], look[0] * up[1] - look[1] * up[0]
    rn = math.sqrt(rx * rx + ry * ry + rz * rz) or 1.0
    right = (rx / rn, ry / rn, rz / rn)
    u = (right[1] * look[2] - right[2] * look[1], right[2] * look[0] - right[0] * look[2], right[0] * look[1] - right[1] * look[0])
    back = (-look[0], -look[1], -look[2])
    return {"p": list(eye), "r": [right[0], u[0], back[0], right[1], u[1], back[1], right[2], u[2], back[2]], "fov": fov}


# the cameras of CameraController (hub + explore), relative to the hero's root
def hub_cam(root):
    fov, dist, side = 40, 15.5, 15.5 * math.tan(math.radians(20)) * (W / H) * 0.5
    eye = (root[0] + side, root[1] + 1.2, root[2] - dist)
    return look_at(eye, (root[0] + side, root[1] - 0.3, root[2]), fov)


def explore_cam(root):
    fov, dist = 55, 21
    side = dist * math.tan(math.radians(fov / 2)) * (W / H) * 0.3
    eye = (root[0] + side, root[1] + 7, root[2] - dist)
    return look_at(eye, (root[0] + side, root[1] + 2.5, root[2]), fov)


FACES = {
    # face: (normal, u direction (left -> right as seen from outside), v direction (top -> bottom), width axis, height axis)
    "Front": ((0, 0, -1), (-1, 0, 0), (0, -1, 0), 0, 1),
    "Back": ((0, 0, 1), (1, 0, 0), (0, -1, 0), 0, 1),
    "Right": ((1, 0, 0), (0, 0, -1), (0, -1, 0), 2, 1),
    "Left": ((-1, 0, 0), (0, 0, 1), (0, -1, 0), 2, 1),
    "Top": ((0, 1, 0), (1, 0, 0), (0, 0, 1), 0, 2),
    "Bottom": ((0, -1, 0), (1, 0, 0), (0, 0, -1), 0, 2),
}


def text_items(data, cam, eye, far=260):
    """(depth, draw function) for every sign label facing the camera, and every floating label"""
    items = []
    for sgn in data["texts"]:
        normal, udir, vdir, wa, ha = FACES.get(sgn["face"], FACES["Front"])
        p, r, s = sgn["p"], sgn["r"], sgn["s"]
        half = [s[0] / 2, s[1] / 2, s[2] / 2]
        center_local = [normal[i] * half[i] for i in range(3)]
        center = render3d._xf(p, r, center_local)
        n_world = render3d._rot(r, normal)
        to_eye = [eye[i] - center[i] for i in range(3)]
        if sum(n_world[i] * to_eye[i] for i in range(3)) <= 0:
            continue
        if math.sqrt(sum(v * v for v in to_eye)) > far:
            continue
        width, height = s[wa], s[ha]
        for lab in sgn["labels"]:
            corners = []
            ok = True
            for uu, vv in ((lab["x"], lab["y"]), (lab["x"] + lab["w"], lab["y"]), (lab["x"] + lab["w"], lab["y"] + lab["h"]), (lab["x"], lab["y"] + lab["h"])):
                local = [center_local[i] + (uu - 0.5) * width * udir[i] + (vv - 0.5) * height * vdir[i] - normal[i] * -0.02 for i in range(3)]
                v = cam.view(render3d._xf(p, r, local))
                if v[2] < 0.5:
                    ok = False
                    break
                corners.append(cam.screen(v))
            if not ok:
                continue
            depth = cam.view(center)[2] - 0.05
            items.append((depth, ("sign", corners, lab, sgn["glow"])))
    for bb in data["billboards"]:
        v = cam.view(bb["p"])
        if v[2] < 1 or v[2] > bb.get("far", 200):
            continue
        cx, cy = cam.screen(v)
        scale = cam.f * cam.h / (2 * v[2])  # pixels per stud at that depth
        w, h = bb["w"] * scale, bb["h"] * scale
        items.append((v[2] - 1.5, ("bill", (cx - w / 2, cy - h / 2, w, h), bb["labels"])))
    return items


def draw_text_box(d, box, lab, glow):
    x0, y0, w, h = box
    txt = lab.get("text", "")
    if lab.get("bg"):
        d.rectangle([x0, y0, x0 + w, y0 + h], fill=tuple(int(c * 255) for c in lab["bg"]) + (255,))
    if not txt or w < 3 or h < 3:
        return
    lines = txt.split("\n")
    kind = "mono" if lab.get("font") == "Code" else "bold"
    longest = max(len(l) for l in lines) or 1
    size = min(h / len(lines) * 0.82, w / (longest * 0.62))
    if size < 5:
        return
    f = font(size, kind)
    col = tuple(int(c * 255) for c in lab["c"]) + (255,)
    stroke = max(1, int(size / 14)) if lab.get("font") == "LuckiestGuy" else 0
    lh = h / len(lines)
    for i, line in enumerate(lines):
        d.text((x0 + w / 2, y0 + lh * (i + 0.5)), line, fill=col, font=f, anchor="mm", stroke_width=stroke, stroke_fill=(24, 18, 44, 255))


def draw_sign(d, corners, lab, glow):
    xs = [c[0] for c in corners]
    ys = [c[1] for c in corners]
    box = (min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys))
    if lab.get("bg"):
        d.polygon(corners, fill=tuple(int(c * 255) for c in lab["bg"]) + (255,))
        lab = dict(lab, bg=None)
    draw_text_box(d, box, lab, glow)


def render(data, cam_dict, hero_root=None, size=(W, H)):
    w, h = size
    cam = render3d.Camera(cam_dict, w, h)
    lt = data["light"]
    fogc = lt.get("fogColor", [0.8, 0.86, 0.95])
    light = render3d.Light(
        direction=tuple(lt["sun"]),
        ambient=tuple(lt["ambient"]),
        points=[(tuple(pl["p"]), pl["range"], pl["brightness"], tuple(pl["c"])) for pl in data["lights"]],
        fog=(lt.get("fogDensity", 0.003) * 0.6, fogc),
    )
    img = render3d.sky(size, (0.42, 0.6, 0.9), tuple(fogc), cam)
    parts = list(data["parts"])
    if hero_root:
        for hp in data["hero"]:
            q = dict(hp)
            q["p"] = [hp["p"][0] + hero_root[0], hp["p"][1] + hero_root[1], hp["p"][2] + hero_root[2]]
            parts.append(q)
    # layers, like the scene really stacks (the cameras are always above the island): what is
    # below the island, then the ground slabs from low to high, then everything else in depth
    # order (thin inlays a touch forward)
    below = [p for p in parts if p.get("name") in BELOW]
    ground = sorted([p for p in parts if p.get("name") in GROUND], key=lambda p: p["p"][1] + (p["s"][0] / 2 if p.get("shape") == "Cylinder" else p["s"][1] / 2))
    rest = [p for p in parts if p.get("name") not in BELOW and p.get("name") not in GROUND]

    def thin(p):
        sz = p["s"]
        return (p.get("shape") == "Cylinder" and sz[0] <= 0.12) or min(sz) <= 0.08

    underlay = sorted(render3d.collect(below, cam, light, big=True, cull_far=900), key=lambda it: -it[0])
    for g in ground:
        underlay += sorted(render3d.collect([g], cam, light, big=True, cull_far=900), key=lambda it: -it[0])
    items = render3d.collect([p for p in rest if not thin(p)], cam, light, big=True, cull_far=900)
    items += [(it[0] - 0.6,) + tuple(it[1:]) for it in render3d.collect([p for p in rest if thin(p)], cam, light, big=True, cull_far=900)]
    eye = cam_dict["p"]
    texts = text_items(data, cam, eye)
    if hero_root:
        render3d.shadows(img, cam, [[[hero_root[0], hero_root[1] - 2.95, hero_root[2]], 1.9]])
    # faces and texts in one back-to-front order
    merged = [(it[0], "face", it) for it in items] + [(t[0], "text", t[1]) for t in texts]
    merged.sort(key=lambda m: -m[0])
    merged = [(it[0], "face", it) for it in underlay] + merged
    d = ImageDraw.Draw(img, "RGBA")
    glow_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow_layer, "RGBA")
    for _, kind, it in merged:
        if kind == "face":
            depth, pts, rgba, is_neon, transparent, _ = it
            if len(pts) < 3:
                continue
            if transparent:
                x0 = max(0, int(min(q[0] for q in pts)) - 1)
                y0 = max(0, int(min(q[1] for q in pts)) - 1)
                x1 = min(w, int(max(q[0] for q in pts)) + 2)
                y1 = min(h, int(max(q[1] for q in pts)) + 2)
                if x1 <= x0 or y1 <= y0:
                    continue
                layer = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
                ImageDraw.Draw(layer).polygon([(q[0] - x0, q[1] - y0) for q in pts], fill=rgba)
                img.alpha_composite(layer, (x0, y0))
                d = ImageDraw.Draw(img, "RGBA")
            else:
                d.polygon(pts, fill=rgba, outline=rgba)
            if is_neon:
                gd.polygon(pts, fill=(rgba[0], rgba[1], rgba[2], 150))
        else:
            if it[0] == "sign":
                draw_sign(d, it[1], it[2], it[3])
            else:
                x0, y0, bw, bh = it[1]
                y = y0
                for lab in it[2]:
                    lh = lab["h"] * bh
                    draw_text_box(d, (x0 + lab["x"] * bw, y0 + lab["y"] * bh, lab["w"] * bw, lh), lab, True)
                    y += lh
    blurred = glow_layer.filter(ImageFilter.GaussianBlur(max(3, int(h / 90))))
    img.alpha_composite(blurred)
    return img


def label(img, text):
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 12 + 9 * len(text), 26], fill=(20, 16, 34, 200))
    d.text((8, 5), text, fill=(255, 226, 120, 255), font=font(15))
    return img


def views(data):
    o = data["origin"]

    def at(x, y, z):
        return (o[0] + x, o[1] + y, o[2] + z)

    stage_root = (o[0], o[1] + 3.7, o[2])
    return {
        "hub": (hub_cam(stage_root), stage_root),
        "camp": (explore_cam(at(20, 3.1, -26)), at(20, 3.1, -26)),
        "departures": (explore_cam(at(-22, 3.1, -24)), at(-22, 3.1, -24)),
        "plaza": (explore_cam(at(0, 3.2, 30)), at(0, 3.2, 30)),
        "park": (explore_cam(at(46, 3.1, 84)), at(46, 3.1, 84)),
        "yard": (explore_cam(at(-50, 3.1, 108)), at(-50, 3.1, 108)),
        "rift": (explore_cam(at(32, 9.1, 152)), at(32, 9.1, 152)),
        "summit": (explore_cam(at(-42, 17, 192)), at(-42, 17, 192)),
        "gate67": (explore_cam(at(-52, 17, 188)), at(-52, 17, 188)),
        "bridge": (explore_cam(at(-8, 12, 176)), at(-8, 12, 176)),
        "nowhere": (explore_cam(at(-86, 16.5, 110)), at(-86, 16.5, 110)),
        "overview": (look_at(at(120, 150, -120), at(-5, 0, 95), 50), None),
        "plan": (look_at(at(0, 520, 95), at(0, 0, 95.5), 42), None),
    }


def main():
    data = json.load(open(SRC))
    want = sys.argv[1:]
    all_views = views(data)
    names = want or list(all_views.keys())
    done = []
    for name in names:
        cam, root = all_views[name]
        img = render(data, cam, root)
        label(img, name.upper())
        path = os.path.join(OUT, name + ".png")
        img.convert("RGB").save(path)
        done.append((name, img))
        print(path)
    # a contact sheet of everything drawn
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
