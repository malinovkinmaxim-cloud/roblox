#!/usr/bin/env python3
"""
A tiny software renderer for the visual check (used by tools/render_gui.py).

Draws Roblox parts the way they look in the game closely enough to judge shapes, colours and
composition: Block / Ball / Cylinder / Wedge parts and SpecialMesh Sphere (ellipsoids) and
Brick meshes are tessellated into faces, lit (ambient + one directional light + point lights),
depth-sorted (painter's algorithm, faces clipped at the near plane) and filled with Pillow.
Neon glows, Metal gets a small highlight, Glass / ForceField are see-through, far faces
fade into the sky (Atmosphere) and can be blurred (DepthOfField).

Input part dict (from tools/export_gui.luau):
  p [x y z]   r [9 rotation values, row-major]   s [size]   c [r g b 0..1]   t transparency
  shape Block|Ball|Cylinder|Wedge|CornerWedge   mat material name   neon bool
  mesh {type, scale [3], offset [3]} (optional SpecialMesh)
"""
import math

from PIL import Image, ImageChops, ImageDraw, ImageFilter

NEAR = 0.1


def _norm(v):
    n = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) or 1.0
    return (v[0] / n, v[1] / n, v[2] / n)


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


# --------------------------------------------------------------------------- camera
class Camera:
    """cam: {p, r, fov}: a Roblox camera CFrame (LookVector = -Z; the offline engine gives the
    scripts Roblox's CFrame.lookAt, see tests/engine.luau)."""

    def __init__(self, cam, width, height):
        r = cam["r"]
        self.pos = tuple(cam["p"])
        look = _norm((-r[2], -r[5], -r[8]))
        rx, rz = -look[2], look[0]
        rl = math.hypot(rx, rz) or 1.0
        self.right = (rx / rl, 0.0, rz / rl)
        self.up = _cross(self.right, look)
        self.look = look
        self.f = 1 / math.tan(math.radians(cam.get("fov", 70)) / 2)
        self.w, self.h = width, height
        self.aspect = width / max(1, height)

    def view(self, p):
        d = (p[0] - self.pos[0], p[1] - self.pos[1], p[2] - self.pos[2])
        return (_dot(d, self.right), _dot(d, self.up), _dot(d, self.look))

    def screen(self, v):
        x, y, z = v
        sx = x / z * self.f / self.aspect
        sy = y / z * self.f
        return ((sx * 0.5 + 0.5) * self.w, (0.5 - sy * 0.5) * self.h)


def _clip_near(poly):
    """Sutherland-Hodgman against z >= NEAR (view space)"""
    out = []
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        ain, bin_ = a[2] >= NEAR, b[2] >= NEAR
        if ain:
            out.append(a)
        if ain != bin_:
            t = (NEAR - a[2]) / (b[2] - a[2])
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, NEAR))
    return out


# --------------------------------------------------------------------------- tessellation
def _xf(p, r, v):
    return (
        p[0] + r[0] * v[0] + r[1] * v[1] + r[2] * v[2],
        p[1] + r[3] * v[0] + r[4] * v[1] + r[5] * v[2],
        p[2] + r[6] * v[0] + r[7] * v[1] + r[8] * v[2],
    )


def _rot(r, v):
    return (r[0] * v[0] + r[1] * v[1] + r[2] * v[2], r[3] * v[0] + r[4] * v[1] + r[5] * v[2], r[6] * v[0] + r[7] * v[1] + r[8] * v[2])


def _subdivide(quad, n, m):
    """a planar quad (4 local points) split into n x m quads"""
    a, b, c, d = quad
    out = []
    for i in range(n):
        for j in range(m):
            u0, u1, v0, v1 = i / n, (i + 1) / n, j / m, (j + 1) / m

            def at(u, v):
                return tuple(a[k] * (1 - u) * (1 - v) + b[k] * u * (1 - v) + c[k] * u * v + d[k] * (1 - u) * v for k in range(3))

            out.append([at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)])
    return out


def _box(sx, sy, sz, big):
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    faces = [
        ((1, 0, 0), [(hx, -hy, -hz), (hx, hy, -hz), (hx, hy, hz), (hx, -hy, hz)]),
        ((-1, 0, 0), [(-hx, -hy, hz), (-hx, hy, hz), (-hx, hy, -hz), (-hx, -hy, -hz)]),
        ((0, 1, 0), [(-hx, hy, -hz), (-hx, hy, hz), (hx, hy, hz), (hx, hy, -hz)]),
        ((0, -1, 0), [(-hx, -hy, hz), (-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz)]),
        ((0, 0, 1), [(hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz), (-hx, -hy, hz)]),
        ((0, 0, -1), [(-hx, -hy, -hz), (-hx, hy, -hz), (hx, hy, -hz), (hx, -hy, -hz)]),
    ]
    out = []
    for n, quad in faces:
        # big faces are split so fog and point lights vary across them
        e1 = math.dist(quad[0], quad[1])
        e2 = math.dist(quad[1], quad[2])
        if big and (e1 > 14 or e2 > 14):
            ni, nj = max(1, min(14, int(e1 / 10))), max(1, min(14, int(e2 / 10)))
            q = [quad[0], quad[1], quad[2], quad[3]]
            # _subdivide walks a->b (u) and a->d (v)
            for sub in _subdivide([q[0], q[1], q[2], q[3]], ni, nj):
                out.append((n, sub))
        else:
            out.append((n, quad))
    return out


def _wedge(sx, sy, sz):
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    slope = _norm((0, sz, -sy))
    return [
        ((0, -1, 0), [(-hx, -hy, hz), (-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz)]),
        ((0, 0, 1), [(hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz), (-hx, -hy, hz)]),
        (slope, [(-hx, -hy, -hz), (-hx, hy, hz), (hx, hy, hz), (hx, -hy, -hz)]),
        ((1, 0, 0), [(hx, -hy, -hz), (hx, hy, hz), (hx, -hy, hz)]),
        ((-1, 0, 0), [(-hx, -hy, hz), (-hx, hy, hz), (-hx, -hy, -hz)]),
    ]


def _ellipsoid(a, b, c, nu=16, nv=10):
    rows = []
    for i in range(nv + 1):
        phi = math.pi * i / nv - math.pi / 2
        cp, sp = math.cos(phi), math.sin(phi)
        rows.append([(a * cp * math.cos(2 * math.pi * j / nu), b * sp, c * cp * math.sin(2 * math.pi * j / nu)) for j in range(nu)])
    out = []
    for i in range(nv):
        for j in range(nu):
            j2 = (j + 1) % nu
            quad = [rows[i][j], rows[i + 1][j], rows[i + 1][j2], rows[i][j2]]
            cx = sum(q[0] for q in quad) / 4
            cy = sum(q[1] for q in quad) / 4
            cz = sum(q[2] for q in quad) / 4
            n = _norm((cx / (a * a or 1), cy / (b * b or 1), cz / (c * c or 1)))
            out.append((n, quad))
    return out


def _cylinder_x(length, radius, seg=18):
    h = length / 2
    ring = [(math.cos(2 * math.pi * k / seg), math.sin(2 * math.pi * k / seg)) for k in range(seg)]
    out = []
    for k in range(seg):
        (c0, s0), (c1, s1) = ring[k], ring[(k + 1) % seg]
        n = _norm((0, (c0 + c1) / 2, (s0 + s1) / 2))
        out.append((n, [(-h, c0 * radius, s0 * radius), (h, c0 * radius, s0 * radius), (h, c1 * radius, s1 * radius), (-h, c1 * radius, s1 * radius)]))
    out.append(((1, 0, 0), [(h, c * radius, s * radius) for c, s in ring]))
    out.append(((-1, 0, 0), [(-h, c * radius, s * radius) for c, s in reversed(ring)]))
    return out


def _cylinder_y(length, rx, rz, seg=18):
    h = length / 2
    ring = [(math.cos(2 * math.pi * k / seg), math.sin(2 * math.pi * k / seg)) for k in range(seg)]
    out = []
    for k in range(seg):
        (c0, s0), (c1, s1) = ring[k], ring[(k + 1) % seg]
        n = _norm(((c0 + c1) / 2 / (rx or 1), 0, (s0 + s1) / 2 / (rz or 1)))
        out.append((n, [(c0 * rx, -h, s0 * rz), (c0 * rx, h, s0 * rz), (c1 * rx, h, s1 * rz), (c1 * rx, -h, s1 * rz)]))
    out.append(((0, 1, 0), [(c * rx, h, s * rz) for c, s in ring]))
    out.append(((0, -1, 0), [(c * rx, -h, s * rz) for c, s in reversed(ring)]))
    return out


def part_faces(part, big=False, detail=1.0):
    """local faces (normal, [points]) of a part, plus the local offset of its mesh"""
    s = part["s"]
    mesh = part.get("mesh")
    offset = (0.0, 0.0, 0.0)
    nu, nv = max(8, int(16 * detail)), max(6, int(10 * detail))
    if mesh:
        sc = mesh.get("scale", [1, 1, 1])
        offset = tuple(mesh.get("offset", [0, 0, 0]))
        mt = mesh.get("type", "Brick")
        if mt == "Sphere":
            return _ellipsoid(s[0] * sc[0] / 2, s[1] * sc[1] / 2, s[2] * sc[2] / 2, nu, nv), offset
        if mt == "Cylinder":
            return _cylinder_y(s[1] * sc[1], s[0] * sc[0] / 2, s[2] * sc[2] / 2), offset
        if mt == "Head":
            # the classic head: a rounded cylinder (drawn as an ellipsoid-ish drum)
            return _cylinder_y(s[1] * sc[1] * 0.8, s[0] * sc[0] * 0.3, s[2] * sc[2] * 0.6), offset
        if mt == "Wedge":
            return _wedge(s[0] * sc[0], s[1] * sc[1], s[2] * sc[2]), offset
        if mt == "FileMesh":
            return [], offset
        return _box(s[0] * sc[0], s[1] * sc[1], s[2] * sc[2], big), offset
    shape = part.get("shape", "Block")
    if shape == "Ball":
        r = min(s) / 2
        return _ellipsoid(r, r, r, nu, nv), offset
    if shape == "Cylinder":
        return _cylinder_x(s[0], min(s[1], s[2]) / 2), offset
    if shape == "Wedge":
        return _wedge(s[0], s[1], s[2]), offset
    return _box(s[0], s[1], s[2], big), offset


# --------------------------------------------------------------------------- lighting
class Light:
    def __init__(self, direction=(-0.6, -1, -0.8), ambient=(0.67, 0.66, 0.75), color=(1, 1, 1), points=None, fog=None, sky=None):
        self.to_light = _norm((-direction[0], -direction[1], -direction[2]))
        self.ambient = ambient
        self.color = color
        self.points = points or []  # (pos, range, brightness, color)
        self.fog = fog  # (density, color) or None
        self.sky = sky


def shade(base, normal, center, light, material, eye):
    ndl = max(0.0, _dot(normal, light.to_light))
    # soft wrap lighting: shadowed sides are not pitch black
    wrap = max(0.0, (_dot(normal, light.to_light) + 0.4) / 1.4)
    amb = light.ambient
    k = [amb[i] * 0.62 + light.color[i] * (0.42 * ndl + 0.16 * wrap) for i in range(3)]
    # sky fill from above
    up = max(0.0, normal[1])
    k = [k[i] + 0.1 * up for i in range(3)]
    for pos, rng, bright, col in light.points:
        d = (pos[0] - center[0], pos[1] - center[1], pos[2] - center[2])
        dist = math.sqrt(_dot(d, d))
        if dist < rng:
            fall = (1 - dist / rng) ** 2 * bright * 0.5
            facing = max(0.0, _dot(normal, _norm(d))) * 0.8 + 0.2
            k = [k[i] + col[i] * fall * facing for i in range(3)]
    out = [base[i] * k[i] for i in range(3)]
    if material == "Metal" or material == "DiamondPlate":
        # a small highlight towards the viewer
        view = _norm((eye[0] - center[0], eye[1] - center[1], eye[2] - center[2]))
        half = _norm((light.to_light[0] + view[0], light.to_light[1] + view[1], light.to_light[2] + view[2]))
        spec = max(0.0, _dot(normal, half)) ** 18 * 0.55
        out = [out[i] * 0.92 + spec for i in range(3)]
    elif material in ("SmoothPlastic", "Plastic", "Glass"):
        view = _norm((eye[0] - center[0], eye[1] - center[1], eye[2] - center[2]))
        half = _norm((light.to_light[0] + view[0], light.to_light[1] + view[1], light.to_light[2] + view[2]))
        spec = max(0.0, _dot(normal, half)) ** 30 * 0.12
        out = [out[i] + spec for i in range(3)]
    return [min(1.0, max(0.0, v)) for v in out]


def _fog(col, dist, light):
    if not light.fog:
        return col
    density, fcol = light.fog
    f = 1 - math.exp(-dist * density)
    return [col[i] * (1 - f) + fcol[i] * f for i in range(3)]


# --------------------------------------------------------------------------- rendering
def collect(parts, cam, light, big=False, cull_far=None):
    """projected faces: (depth, points2d, rgba, glow, transparent, depth for the depth of field)"""
    items = []
    eye = cam.pos
    for part in parts:
        t = part.get("t", 0)
        if t >= 0.98:
            continue
        mat = part.get("mat") or ("Neon" if part.get("neon") else "SmoothPlastic")
        p, r = part["p"], part["r"]
        if cull_far is not None:
            v = cam.view(p)
            if v[2] < -max(part["s"]) or v[2] > cull_far:
                continue
        faces, off = part_faces(part, big=big, detail=part.get("_detail", 1.0))
        if not faces:
            continue
        # depth of field sorts whole parts (a pillar is not half sharp, half blurred);
        # only big parts (floors, walls) go face by face
        part_depth = None if max(part["s"]) > 20 else cam.view(p)[2]
        alpha = 1 - t
        base = part["c"]
        if mat == "Glass":
            alpha *= 0.55
        elif mat == "ForceField":
            alpha *= 0.3
            base = [min(1, c * 1.3 + 0.15) for c in base]
        neon = mat == "Neon"
        transparent = alpha < 0.99
        for n_local, pts in faces:
            n = _rot(r, n_local)
            world = [_xf(p, r, (q[0] + off[0], q[1] + off[1], q[2] + off[2])) for q in pts]
            center = (sum(w[0] for w in world) / len(world), sum(w[1] for w in world) / len(world), sum(w[2] for w in world) / len(world))
            to_eye = (eye[0] - center[0], eye[1] - center[1], eye[2] - center[2])
            if _dot(n, to_eye) <= 0 and len(world) >= 3:
                continue  # back face
            vpts = [cam.view(w) for w in world]
            if max(v[2] for v in vpts) < NEAR:
                continue
            if min(v[2] for v in vpts) < NEAR:
                vpts = _clip_near(vpts)
                if len(vpts) < 3:
                    continue
            depth = sum(v[2] for v in vpts) / len(vpts)
            pts2 = [cam.screen(v) for v in vpts]
            if neon:
                col = [min(1.0, c * 1.12 + 0.1) for c in base]
            else:
                col = shade(base, n, center, light, mat, eye)
            dist = math.sqrt(_dot(to_eye, to_eye))
            col = _fog(col, dist, light)
            rgba = (int(col[0] * 255 + 0.5), int(col[1] * 255 + 0.5), int(col[2] * 255 + 0.5), int(alpha * 255 + 0.5))
            items.append((depth, pts2, rgba, neon and alpha > 0.3, transparent, depth if part_depth is None else part_depth))
    return items


def draw_items(img, items, glow=True, glow_radius=6):
    items.sort(key=lambda it: -it[0])
    d = ImageDraw.Draw(img, "RGBA")
    glow_layer = None
    if glow and any(it[3] for it in items):
        glow_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow_layer, "RGBA")
    for depth, pts, rgba, is_neon, transparent, _ in items:
        if len(pts) < 3:
            continue
        if transparent:
            # blend through a layer the size of the face only
            x0 = max(0, int(min(q[0] for q in pts)) - 1)
            y0 = max(0, int(min(q[1] for q in pts)) - 1)
            x1 = min(img.size[0], int(max(q[0] for q in pts)) + 2)
            y1 = min(img.size[1], int(max(q[1] for q in pts)) + 2)
            if x1 <= x0 or y1 <= y0:
                continue
            layer = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
            ImageDraw.Draw(layer).polygon([(q[0] - x0, q[1] - y0) for q in pts], fill=rgba)
            img.alpha_composite(layer, (x0, y0))
        else:
            # a hairline of the same colour hides the seams between neighbouring faces
            d.polygon(pts, fill=rgba, outline=rgba)
        if glow_layer is not None and is_neon:
            gd.polygon(pts, fill=(rgba[0], rgba[1], rgba[2], 150))
    if glow_layer is not None:
        blurred = glow_layer.filter(ImageFilter.GaussianBlur(glow_radius))
        # additive-ish: lighten with the blurred glow
        img.alpha_composite(blurred)
    return img


def shadows(img, cam, blobs):
    """soft contact shadows: blobs = [(pos, radius)] on the ground plane at pos.y"""
    if not blobs:
        return
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for pos, radius in blobs:
        pts = []
        for k in range(20):
            a = 2 * math.pi * k / 20
            v = cam.view((pos[0] + math.cos(a) * radius, pos[1], pos[2] + math.sin(a) * radius))
            if v[2] < NEAR:
                pts = []
                break
            pts.append(cam.screen(v))
        if len(pts) >= 3:
            d.polygon(pts, fill=(10, 8, 20, 110))
    blur = max(2, int(img.size[1] / 180))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))


def sky(size, top=(0.43, 0.63, 0.9), horizon=(0.8, 0.87, 0.96), cam=None):
    w, h = size
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    # horizon line from the camera pitch
    hy = h * 0.5
    if cam:
        pitch = math.asin(max(-1, min(1, cam.look[1])))
        hy = h * (0.5 + math.tan(pitch) * cam.f * 0.5)
    for y in range(h):
        t = max(0.0, min(1.0, (hy - y) / max(1.0, h * 0.8)))
        c = [horizon[i] * (1 - t) + top[i] * t for i in range(3)]
        d.line((0, y, w, y), fill=(int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), 255))
    return img


def render_viewport(size, cam_dict, parts, light, tint=(1, 1, 1)):
    """a ViewportFrame's content on a transparent layer"""
    w, h = size
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cam = Camera(cam_dict, w, h)
    if tint != (1, 1, 1) and tint != [1, 1, 1]:
        parts = [dict(pt, c=[pt["c"][i] * tint[i] for i in range(3)]) for pt in parts]
    items = collect(parts, cam, light)
    draw_items(img, items, glow=True, glow_radius=max(2, int(h / 60)))
    return img


def render_world(size, world):
    """the 3D world behind the UI: sky, parts, contact shadows, glow, depth of field"""
    w, h = size
    cam = Camera(world["cam"], w, h)
    lt = world.get("light", {})
    fogc = lt.get("fogColor", [0.8, 0.86, 0.95])
    light = Light(
        direction=tuple(lt.get("sun", [-0.35, -0.85, -0.4])),
        ambient=tuple(lt.get("ambient", [0.62, 0.62, 0.7])),
        color=tuple(lt.get("sunColor", [1, 0.98, 0.92])),
        points=[(tuple(pl["p"]), pl["range"], pl["brightness"], tuple(pl["c"])) for pl in world.get("lights", [])],
        fog=(lt.get("fogDensity", 0.004), fogc),
    )
    img = sky(size, tuple(lt.get("skyTop", [0.42, 0.6, 0.9])), tuple(fogc), cam)
    items = collect(world["parts"], cam, light, big=True, cull_far=world.get("far", 600))
    dof = world.get("dof")
    if dof:
        split = dof["focus"] + dof["radius"]
        far = [it for it in items if it[5] > split]
        near = [it for it in items if it[5] <= split]
        draw_items(img, far, glow=True, glow_radius=max(3, int(h / 70)))
        img = img.filter(ImageFilter.GaussianBlur(max(1, dof["blur"] * h / 400)))
        shadows(img, cam, world.get("shadows", []))
        draw_items(img, near, glow=True, glow_radius=max(3, int(h / 70)))
    else:
        shadows(img, cam, world.get("shadows", []))
        draw_items(img, items, glow=True, glow_radius=max(3, int(h / 70)))
    cc = world.get("tint")
    if cc:
        # ColorCorrection.TintColor multiplies the final picture
        tint = Image.new("RGB", size, (int(cc[0] * 255), int(cc[1] * 255), int(cc[2] * 255)))
        img = ImageChops.multiply(img.convert("RGB"), tint).convert("RGBA")
    return img
