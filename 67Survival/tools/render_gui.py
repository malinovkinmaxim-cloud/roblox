#!/usr/bin/env python3
"""
Visual check, part 2: lays out the GUI trees written by tools/export_gui.luau the way Roblox
does (UDim2 scale + offset, AnchorPoint, UIScale, UIPadding, UIListLayout, UIGridLayout,
UISizeConstraint, TextScaled + UITextSizeConstraint, AutomaticSize for text, ZIndex, clipping
of ScrollingFrames) and draws PNGs with Pillow at several screen sizes.

It also reports layout problems: text that had to shrink far below its intended size,
elements that stick out of the screen, and overlapping siblings.

usage: python3 tools/render_gui.py <json-dir> <out-dir> [scene ...]   (or tools/ui_check.sh)
       (needs Pillow; fonts: DejaVu Sans stands in for Builder Sans - a bit wider, so text
        that fits here fits in Roblox too)

Approximations: 3D previews (ViewportFrames) are drawn as flat projected boxes / balls,
avatar thumbnails as a placeholder, and the 3D world behind the UI as a simple painted scene.
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SS = 2  # supersampling
DESIGN = (1100, 620)
COMPACT = (1000, 520)  # phones (touch, short screens): Theme.CompactDesignSize
SIZES = {
    "1920x1080": (1920, 1080),
    "1600x900": (1600, 900),
    "1366x768": (1366, 768),
    "tablet-1024x768": (1024, 768),
    "phone-844x390": (844, 390),
}
FONT_FILES = {
    "bold": "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "regular": "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
}
FONT_STYLE = {
    "BuilderSansExtraBold": "bold",
    "BuilderSansBold": "bold",
    "BuilderSansMedium": "regular",
    "BuilderSans": "regular",
    "LuckiestGuy": "bold",
}
GUI = {"Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame", "ViewportFrame", "CanvasGroup"}
TEXT = {"TextLabel", "TextButton", "TextBox"}

_fonts = {}


def font(style, size):
    size = max(1, int(round(size)))
    key = (style, size)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(FONT_FILES[style], size)
    return _fonts[key]


def kid(node, cls):
    for k in node.get("kids", []):
        if k["c"] == cls:
            return k
    return None


def rgba(c, transparency=0.0):
    return (int(c[0] * 255 + 0.5), int(c[1] * 255 + 0.5), int(c[2] * 255 + 0.5), int(max(0.0, min(1.0, 1 - transparency)) * 255 + 0.5))


# --------------------------------------------------------------------------- text
def line_height(size):
    return size * 1.18


def text_width(style, size, text):
    if not text:
        return 0
    return font(style, size).getlength(text)


def wrap_lines(style, size, text, width, wrap):
    out = []
    for para in text.split("\n"):
        if not wrap:
            out.append(para)
            continue
        words = para.split(" ")
        line = ""
        for w in words:
            trial = w if not line else line + " " + w
            if text_width(style, size, trial) <= width or not line:
                line = trial
            else:
                out.append(line)
                line = w
        out.append(line)
    return out


def fits(style, size, text, w, h, wrap):
    lines = wrap_lines(style, size, text, w, wrap)
    if len(lines) * line_height(size) > h + 0.5:
        return False, lines
    for ln in lines:
        if text_width(style, size, ln) > w + 0.5:
            return False, lines
    return True, lines


def text_size_for(node, w, h, k):
    """final pixel text size and the lines; plus the size the author intended (for the report)"""
    style = FONT_STYLE.get(node.get("font"), "bold")
    text = node.get("text") or ""
    if node["c"] == "TextBox" and not text:
        text = node.get("ph") or ""
    constraint = kid(node, "UITextSizeConstraint")
    wrap = node.get("wrap") or node.get("scaled")
    if node.get("scaled"):
        cap = 100 * k
        if constraint:
            cap = min(cap, constraint["maxts"] * k)
        lo, hi = 1.0, cap
        best = 1.0
        # the largest size that fits (binary search on half pixels)
        for _ in range(18):
            mid = (lo + hi) / 2
            ok, _ = fits(style, mid, text, w, h, wrap)
            if ok:
                best = mid
                lo = mid
            else:
                hi = mid
        if fits(style, cap, text, w, h, wrap)[0]:
            best = cap
        _, lines = fits(style, best, text, w, h, wrap)
        return style, best, lines, cap
    size = node.get("ts", 14) * k
    lines = wrap_lines(style, size, text, w, wrap)
    return style, size, lines, size


# --------------------------------------------------------------------------- layout
class Ctx:
    def __init__(self, screen):
        self.screen = screen
        self.issues = []


def auto_text_width(node, k):
    style = FONT_STYLE.get(node.get("font"), "bold")
    size = node.get("ts", 14) * k
    text = node.get("text") or ""
    pad = kid(node, "UIPadding")
    extra = 0
    if pad:
        extra = (pad["pad"][0][1] + pad["pad"][1][1]) * k
    return max((text_width(style, size, ln) for ln in text.split("\n")), default=0) + extra


def measure(node, pw, ph, k):
    """own size before UIScale (w, h) and the scale factor of its UIScale"""
    s = node["size"]
    w = s[0] * pw + s[1] * k
    h = s[2] * ph + s[3] * k
    auto = node.get("auto")
    if node["c"] in TEXT and auto in ("X", "XY") and not node.get("scaled"):
        w = max(w, auto_text_width(node, k))
    if node["c"] in TEXT and auto in ("Y", "XY"):
        style, size, lines, _ = text_size_for(node, w, 1e9, k)
        h = max(h, len(lines) * line_height(size))
    con = kid(node, "UISizeConstraint")
    if con:
        w = min(max(w, con["min"][0] * k), con["max"][0] * k)
        h = min(max(h, con["min"][1] * k), con["max"][1] * k)
    sc = kid(node, "UIScale")
    scale = sc["scale"] if sc else 1.0
    return w, h, scale


def sorted_children(node, layout):
    kids = [c for c in node.get("kids", []) if c["c"] in GUI]
    if layout and layout.get("sort") == "LayoutOrder":
        return sorted(enumerate(kids), key=lambda t: (t[1].get("order", 0), t[0]))
    if layout:
        return sorted(enumerate(kids), key=lambda t: (t[1]["n"], t[0]))
    return list(enumerate(kids))


def layout(node, px, py, pw, ph, k, forced=None):
    if forced:
        x, y, w, h = forced
        sc = kid(node, "UIScale")
        scale = sc["scale"] if sc else 1.0
        if scale != 1.0:
            cx, cy = x + w / 2, y + h / 2
            w, h = w * scale, h * scale
            x, y = cx - w / 2, cy - h / 2
    else:
        w, h, scale = measure(node, pw, ph, k)
        w0, h0 = w, h
        w, h = w * scale, h * scale
        p = node["pos"]
        ax, ay = node["anchor"]
        # UIScale grows the object around its anchor point
        x = px + p[0] * pw + p[1] * k - ax * w0 - ax * (w - w0)
        y = py + p[2] * ph + p[3] * k - ay * h0 - ay * (h - h0)
    k2 = k * scale
    node["_box"] = (x, y, w, h)
    node["_k"] = k2
    pad = kid(node, "UIPadding")
    cx, cy, cw, ch = x, y, w, h
    if pad:
        (ls, lo), (rs, ro), (ts, to), (bs, bo) = pad["pad"]
        pl, pr, pt, pb = ls * w + lo * k2, rs * w + ro * k2, ts * h + to * k2, bs * h + bo * k2
        cx, cy, cw, ch = x + pl, y + pt, w - pl - pr, h - pt - pb
    if node["c"] == "ScrollingFrame":
        cw -= 0  # scrollbar overlays in this approximation
    lst = kid(node, "UIListLayout")
    grid = kid(node, "UIGridLayout")
    kids = sorted_children(node, lst or grid)
    if lst:
        horizontal = lst.get("dir") == "Horizontal"
        visible = [c for _, c in kids if c.get("vis", True)]
        sizes = []
        for c in visible:
            cw_, ch_, sc_ = measure(c, cw, ch, k2)
            sizes.append((cw_ * sc_, ch_ * sc_))
        padding = lst["padding"][0] * (cw if horizontal else ch) + lst["padding"][1] * k2
        total = sum(s[0] if horizontal else s[1] for s in sizes) + padding * max(0, len(sizes) - 1)
        ha, va = lst.get("ha", "Left"), lst.get("va", "Top")
        if horizontal:
            pos = cx + {"Left": 0, "Center": (cw - total) / 2, "Right": cw - total}.get(ha, 0)
        else:
            pos = cy + {"Top": 0, "Center": (ch - total) / 2, "Bottom": ch - total}.get(va, 0)
        for c, (sw, sh) in zip(visible, sizes):
            if horizontal:
                yy = cy + {"Top": 0, "Center": (ch - sh) / 2, "Bottom": ch - sh}.get(va, 0)
                layout(c, 0, 0, cw, ch, k2, (pos, yy, sw, sh))
                pos += sw + padding
            else:
                xx = cx + {"Left": 0, "Center": (cw - sw) / 2, "Right": cw - sw}.get(ha, 0)
                layout(c, 0, 0, cw, ch, k2, (xx, pos, sw, sh))
                pos += sh + padding
        for _, c in kids:
            if not c.get("vis", True):
                c["_box"] = None
        node["_content"] = pos - (cy if not horizontal else cx)
    elif grid:
        cell = grid["cell"]
        cpad = grid["cellpad"]
        cwid = cell[0] * cw + cell[1] * k2
        chei = cell[2] * ch + cell[3] * k2
        padx = cpad[0] * cw + cpad[1] * k2
        pady = cpad[2] * ch + cpad[3] * k2
        visible = [c for _, c in kids if c.get("vis", True)]
        cols = max(1, int((cw + padx + 0.01) // (cwid + padx))) if cwid + padx > 0 else 1
        n = len(visible)
        used = min(cols, n) if n else 0
        block = used * cwid + max(0, used - 1) * padx
        x0 = cx + {"Left": 0, "Center": (cw - block) / 2, "Right": cw - block}.get(grid.get("ha", "Left"), 0)
        for i, c in enumerate(visible):
            r, col = divmod(i, cols)
            layout(c, 0, 0, cw, ch, k2, (x0 + col * (cwid + padx), cy + r * (chei + pady), cwid, chei))
        rows = (n + cols - 1) // cols if n else 0
        node["_content"] = rows * chei + max(0, rows - 1) * pady
        for _, c in kids:
            if not c.get("vis", True):
                c["_box"] = None
    else:
        for _, c in kids:
            layout(c, cx, cy, cw, ch, k2)


# --------------------------------------------------------------------------- drawing
def corner_radius(node, w, h, k):
    c = kid(node, "UICorner")
    if not c:
        return 0
    r = c["radius"][0] * min(w, h) + c["radius"][1] * k
    return max(0, min(r, min(w, h) / 2))


def gradient_image(w, h, g, base, transparency):
    """UIGradient: colours multiply the base colour, transparency sequence multiplies alpha"""
    w, h = max(1, int(w)), max(1, int(h))
    rot = (g.get("rot") or 0) % 360
    vertical = 45 < rot < 135 or 225 < rot < 315
    reverse = 135 <= rot < 315
    n = h if vertical else w
    strip = Image.new("RGBA", (n, 1))
    cs, ts = g["cs"], g["trs"]

    def sample(seq, t, width):
        for i in range(len(seq) - 1):
            a, b = seq[i], seq[i + 1]
            if a[0] <= t <= b[0]:
                f = 0 if b[0] == a[0] else (t - a[0]) / (b[0] - a[0])
                return [a[j] + (b[j] - a[j]) * f for j in range(1, width + 1)]
        return seq[-1][1 : width + 1]

    for i in range(n):
        t = (i + 0.5) / n
        if reverse:
            t = 1 - t
        col = sample(cs, t, 3)
        tr = sample(ts, t, 1)[0]
        a = (1 - transparency) * (1 - tr)
        strip.putpixel((i, 0), (int(base[0] * col[0] * 255), int(base[1] * col[1] * 255), int(base[2] * col[2] * 255), int(max(0, min(1, a)) * 255)))
    if vertical:
        strip = strip.transpose(Image.Transpose.ROTATE_270).transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        return strip.resize((w, h))
    return strip.resize((w, h))


class Painter:
    def __init__(self, size, background):
        self.img = background.convert("RGBA")
        self.W, self.H = size

    def paste(self, layer, x, y, clip):
        """alpha-composite layer at (x, y) limited to the clip rect"""
        x, y = int(round(x)), int(round(y))
        cx0, cy0, cx1, cy1 = clip
        lx0, ly0 = max(x, cx0), max(y, cy0)
        lx1, ly1 = min(x + layer.width, cx1), min(y + layer.height, cy1)
        if lx1 <= lx0 or ly1 <= ly0:
            return
        part = layer.crop((lx0 - x, ly0 - y, lx1 - x, ly1 - y))
        self.img.alpha_composite(part, (lx0, ly0))

    def rect(self, box, radius, fill, clip, gradient=None, transparency=0.0):
        x, y, w, h = box
        if w < 1 or h < 1:
            return
        iw, ih = int(math.ceil(w)), int(math.ceil(h))
        mask = Image.new("L", (iw, ih), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, iw - 1, ih - 1), radius=radius, fill=255)
        if gradient:
            layer = gradient_image(iw, ih, gradient, fill, transparency)
        else:
            layer = Image.new("RGBA", (iw, ih), rgba(fill, transparency))
        alpha = Image.composite(layer.getchannel("A"), Image.new("L", (iw, ih), 0), mask)
        layer.putalpha(alpha)
        self.paste(layer, x, y, clip)

    def stroke(self, box, radius, thickness, color, transparency, clip):
        x, y, w, h = box
        t = max(1, int(round(thickness)))
        iw, ih = int(math.ceil(w)) + 2 * t, int(math.ceil(h)) + 2 * t
        if iw < 2 or ih < 2:
            return
        layer = Image.new("RGBA", (iw, ih), (0, 0, 0, 0))
        ImageDraw.Draw(layer).rounded_rectangle((0, 0, iw - 1, ih - 1), radius=radius + t, outline=rgba(color, transparency), width=t)
        self.paste(layer, x - t, y - t, clip)

    def text(self, node, box, k, clip, ctx):
        x, y, w, h = box
        text = node.get("text") or ""
        color = node.get("tc", [1, 1, 1])
        transparency = node.get("tt", 0)
        if node["c"] == "TextBox" and not text:
            color = node.get("phc", [0.5, 0.5, 0.5])
        pad = kid(node, "UIPadding")
        if pad:
            (ls, lo), (rs, ro), (ts, to), (bs, bo) = pad["pad"]
            pl, pr, pt, pb = ls * w + lo * k, rs * w + ro * k, ts * h + to * k, bs * h + bo * k
            x, y, w, h = x + pl, y + pt, w - pl - pr, h - pt - pb
        if not text and not (node["c"] == "TextBox" and node.get("ph")):
            return
        if transparency >= 1 or w <= 0 or h <= 0:
            return
        style, size, lines, intended = text_size_for(node, w, h, k)
        if kid(node, "UITextSizeConstraint") and node.get("scaled") and size < intended * 0.62 and intended >= 11 * SS and (node.get("text") or "").strip():
            ctx.issues.append(f"text shrinks to {size / intended:.0%} of its size: '{(node.get('text') or '')[:40]}' in {node['n']}")
        stroke = None
        for s in node.get("kids", []):
            if s["c"] == "UIStroke" and s.get("mode") == "Contextual" and s.get("on", True):
                stroke = s
        f = font(style, size)
        lh = line_height(size)
        total = lh * len(lines)
        ya = node.get("ya", "Center")
        ty = y + {"Top": 0, "Center": (h - total) / 2, "Bottom": h - total}.get(ya, (h - total) / 2)
        xa = node.get("xa", "Center")
        sw = int(round(stroke["th"] * k)) if stroke else 0
        for ln in lines:
            lw = f.getlength(ln)
            tx = x + {"Left": 0, "Center": (w - lw) / 2, "Right": w - lw}.get(xa, (w - lw) / 2)
            iw, ih = int(lw) + 4 + 2 * sw, int(lh) + 4 + 2 * sw
            layer = Image.new("RGBA", (iw, ih), (0, 0, 0, 0))
            d = ImageDraw.Draw(layer)
            asc, desc = f.getmetrics()
            oy = (lh - (asc + desc)) / 2
            if stroke:
                d.text((2 + sw, 2 + sw + oy), ln, font=f, fill=rgba(color, transparency), stroke_width=sw, stroke_fill=rgba(stroke["col"], stroke["tr"]))
            else:
                d.text((2, 2 + oy), ln, font=f, fill=rgba(color, transparency))
            self.paste(layer, tx - 2 - sw, ty - 2 - sw, clip)
            ty += lh
        if node.get("_text_overflow_check", True) and not node.get("scaled"):
            widest = max((f.getlength(ln) for ln in lines), default=0)
            if widest > w + 2 * SS and node.get("auto") not in ("X", "XY"):
                ctx.issues.append(f"text wider than its box: '{text[:40]}' in {node['n']} ({widest / SS:.0f} > {w / SS:.0f})")

    def viewport(self, node, box, clip):
        cam = node.get("cam")
        if not cam:
            return
        x, y, w, h = box
        iw, ih = int(math.ceil(w)), int(math.ceil(h))
        if iw < 2 or ih < 2:
            return
        layer = Image.new("RGBA", (iw, ih), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        cp = cam["p"]
        r = cam["r"]
        # Lune 0.8's CFrame.lookAt faces AWAY from the target (Roblox faces towards it), and the
        # previews build their cameras with lookAt: rebuild the Roblox camera basis from it
        look = (r[2], r[5], r[8])
        rx, rz = -look[2], look[0]
        rl = math.hypot(rx, rz) or 1
        right = (rx / rl, 0.0, rz / rl)
        up = (right[1] * look[2] - right[2] * look[1], right[2] * look[0] - right[0] * look[2], right[0] * look[1] - right[1] * look[0])
        back = (-look[0], -look[1], -look[2])
        f = 1 / math.tan(math.radians(cam["fov"]) / 2)
        aspect = iw / ih
        tint = node.get("ic", [1, 1, 1])

        def project(p):
            dx, dy, dz = p[0] - cp[0], p[1] - cp[1], p[2] - cp[2]
            z = -(dx * back[0] + dy * back[1] + dz * back[2])
            if z <= 0.05:
                return None
            sx = (dx * right[0] + dy * right[1] + dz * right[2]) / z * f / aspect
            sy = (dx * up[0] + dy * up[1] + dz * up[2]) / z * f
            return ((sx * 0.5 + 0.5) * iw, (0.5 - sy * 0.5) * ih, z)

        items = []
        for part in node.get("parts", []):
            if part["t"] >= 1:
                continue
            p, rr, s = part["p"], part["r"], part["s"]
            center = project(p)
            if not center:
                continue
            items.append((center[2], part, center))
        items.sort(key=lambda t: -t[0])
        for z, part, center in items:
            col = [part["c"][i] * tint[i] for i in range(3)]
            if part["neon"]:
                col = [min(1, c * 1.15 + 0.08) for c in col]
            fill = rgba(col, part["t"])
            p, rr, s = part["p"], part["r"], part["s"]
            if part["shape"] == "Ball":
                rad = max(s) / 2 / z * f * ih / 2
                d.ellipse((center[0] - rad, center[1] - rad, center[0] + rad, center[1] + rad), fill=fill)
                continue
            pts = []
            for ix in (-0.5, 0.5):
                for iy in (-0.5, 0.5):
                    for iz in (-0.5, 0.5):
                        lx, ly, lz = ix * s[0], iy * s[1], iz * s[2]
                        wx = p[0] + rr[0] * lx + rr[1] * ly + rr[2] * lz
                        wy = p[1] + rr[3] * lx + rr[4] * ly + rr[5] * lz
                        wz = p[2] + rr[6] * lx + rr[7] * ly + rr[8] * lz
                        q = project((wx, wy, wz))
                        if q:
                            pts.append((q[0], q[1]))
            if len(pts) >= 3:
                hull = convex_hull(pts)
                d.polygon(hull, fill=fill)
                shade = tuple(int(v * 0.8) for v in fill[:3]) + (fill[3],)
                d.line(hull + [hull[0]], fill=shade, width=max(1, SS))
        self.paste(layer, x, y, clip)

    def image(self, node, box, clip):
        img = node.get("img") or ""
        x, y, w, h = box
        if "AvatarHeadShot" in img:
            iw, ih = int(w), int(h)
            if iw < 4:
                return
            layer = Image.new("RGBA", (iw, ih), (0, 0, 0, 0))
            d = ImageDraw.Draw(layer)
            d.ellipse((iw * 0.18, ih * 0.1, iw * 0.82, ih * 0.74), fill=(245, 205, 160, 255))
            d.ellipse((iw * 0.34, ih * 0.36, iw * 0.42, ih * 0.44), fill=(40, 40, 40, 255))
            d.ellipse((iw * 0.58, ih * 0.36, iw * 0.66, ih * 0.44), fill=(40, 40, 40, 255))
            mask = Image.new("L", (iw, ih), 0)
            ImageDraw.Draw(mask).ellipse((0, 0, iw - 1, ih - 1), fill=255)
            layer.putalpha(Image.composite(layer.getchannel("A"), Image.new("L", (iw, ih), 0), mask))
            self.paste(layer, x, y, clip)


def convex_hull(points):
    pts = sorted(set((round(a, 2), round(b, 2)) for a, b in points))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def draw(node, painter, clip, ctx):
    if not node.get("vis", True) or node.get("_box") is None:
        return
    box = node["_box"]
    k = node["_k"]
    x, y, w, h = box
    cls = node["c"]
    radius = corner_radius(node, w, h, k)
    grad = next((g for g in node.get("kids", []) if g["c"] == "UIGradient" and g.get("on", True)), None)
    bgt = node.get("bgt", 1)
    if bgt < 1 and cls != "ViewportFrame":
        painter.rect(box, radius, node["bg"], clip, grad, bgt)
    elif cls == "ViewportFrame" and bgt < 1:
        painter.rect(box, radius, node["bg"], clip, None, bgt)
    for s in node.get("kids", []):
        if s["c"] == "UIStroke" and s.get("mode") != "Contextual" and s.get("on", True):
            if not (cls in TEXT and bgt >= 1 and not kid(node, "UICorner") and False):
                painter.stroke(box, radius, s["th"] * k, s["col"], s["tr"], clip)
    if cls in TEXT:
        painter.text(node, box, k, clip, ctx)
    elif cls == "ViewportFrame":
        painter.viewport(node, box, clip)
    elif cls in ("ImageLabel", "ImageButton"):
        painter.image(node, box, clip)
    child_clip = clip
    if cls == "ScrollingFrame" or node.get("clip"):
        child_clip = (max(clip[0], int(x)), max(clip[1], int(y)), min(clip[2], int(x + w)), min(clip[3], int(y + h)))
    kids = [c for c in node.get("kids", []) if c["c"] in GUI]
    kids = sorted(enumerate(kids), key=lambda t: (t[1].get("z", 1), t[0]))
    for _, c in kids:
        draw(c, painter, child_clip, ctx)
    if cls == "ScrollingFrame" and node.get("_content", 0) > h + 2:
        # scrollbar hint: content continues
        bar = max(3, int(node.get("bar", 5) * k * 0.6))
        frac = h / node["_content"]
        painter.rect((x + w - bar - 2, y + 2, bar, max(10, (h - 4) * frac)), bar / 2, [0.46, 0.45, 0.57], clip)


# --------------------------------------------------------------------------- checks
def check_bounds(node, screen, ctx, path=""):
    if not node.get("vis", True) or node.get("_box") is None:
        return
    name = path + "/" + node["n"]
    x, y, w, h = node["_box"]
    W, H = screen
    if node["c"] in GUI and w > 2 and h > 2 and node.get("bgt", 1) < 1:
        if x < -1 or y < -1 or x + w > W + 1 or y + h > H + 1:
            ctx.issues.append(f"off screen: {name} ({x / SS:.0f},{y / SS:.0f} {w / SS:.0f}x{h / SS:.0f})")
    if node["c"] == "ScrollingFrame":
        return  # children scroll: may extend past the frame on purpose
    for c in node.get("kids", []):
        if c["c"] in GUI:
            check_bounds(c, screen, ctx, name)


ICONS = {"Gear", "Coin", "Lock", "PauseIcon", "Mono", "Price", "Icon", "Preview", "Picture", "Knob"}


def check_overlaps(node, ctx, path=""):
    """siblings without a layout that overlap each other (only solid, visible ones)"""
    if not node.get("vis", True) or node.get("_box") is None or node["n"] in ICONS:
        return
    name = path + "/" + node["n"]
    kids = [c for c in node.get("kids", []) if c["c"] in GUI and c.get("vis", True) and c.get("_box")]
    managed = kid(node, "UIListLayout") or kid(node, "UIGridLayout")
    if not managed and node["c"] != "ScrollingFrame":
        px, py, pw, ph = node["_box"]
        # full-screen overlays (dims, vignettes) and bar fills sit under other things on purpose
        solid = [
            c
            for c in kids
            if (c.get("bgt", 1) < 0.95 or c["c"] in TEXT and (c.get("text") or "").strip())
            and c["n"] != "Fill"
            and not c["n"].startswith("Vignette")
            and c["_box"][2] * c["_box"][3] < 0.9 * pw * ph
        ]
        for i in range(len(solid)):
            for j in range(i + 1, len(solid)):
                a, b = solid[i]["_box"], solid[j]["_box"]
                ox = min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0])
                oy = min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])
                if ox > 3 * SS and oy > 3 * SS:
                    small = min(a[2] * a[3], b[2] * b[3])
                    if small > 0 and ox * oy / small > 0.02:
                        ctx.issues.append(f"overlap: {name}/{solid[i]['n']} and {solid[j]['n']}")
    for c in kids:
        check_overlaps(c, ctx, name)


# --------------------------------------------------------------------------- scene
def background(size, blur, run):
    """a stand-in for the 3D world: bright sky + grass (lobby) or arena floor (run)"""
    W, H = size
    img = Image.new("RGB", size)
    d = ImageDraw.Draw(img)
    horizon = int(H * 0.42)
    for yy in range(H):
        if yy < horizon:
            t = yy / max(1, horizon)
            c = (int(120 + 60 * t), int(180 + 40 * t), 255)
        else:
            t = (yy - horizon) / max(1, H - horizon)
            c = (int(92 - 30 * t), int(170 - 40 * t), int(80 - 25 * t)) if not run else (int(118 - 30 * t), int(104 - 30 * t), int(140 - 30 * t))
        d.line((0, yy, W, yy), fill=c)
    # a few buildings / props so the UI is judged over a busy, bright picture
    props = [(0.08, 0.3, 0.1, 0.18, (240, 120, 160)), (0.72, 0.26, 0.14, 0.2, (250, 210, 90)), (0.36, 0.33, 0.06, 0.1, (120, 90, 200)), (0.86, 0.34, 0.08, 0.09, (255, 255, 255))]
    for px, py, pw, ph, col in props:
        d.rectangle((px * W, py * H, (px + pw) * W, (py + ph) * H), fill=col)
    # the survivor in the middle
    cx, cy = W * 0.5, H * 0.52
    u = H * 0.03
    d.rectangle((cx - u, cy - u, cx + u, cy + u * 1.2), fill=(120, 220, 90))
    d.rectangle((cx - u * 0.7, cy - u * 2.2, cx + u * 0.7, cy - u * 1.0), fill=(245, 205, 160))
    if run:
        for i in range(26):
            ex = W * (0.15 + 0.7 * ((i * 37) % 100) / 100)
            ey = H * (0.3 + 0.6 * ((i * 53) % 100) / 100)
            d.ellipse((ex - u, ey - u, ex + u, ey + u), fill=(90, 200, 80) if i % 3 else (230, 80, 90))
    if blur > 0:
        img = img.filter(ImageFilter.GaussianBlur(blur * SS * 0.6))
    return img


def refit(node, view_w, view_h):
    """code that sizes things from Kit.View, redone for this screen:
    Widgets.Fit (FitScale) and rows scaled to fit the view (RowFit)"""
    for c in node.get("kids", []):
        if c["c"] != "UIScale":
            continue
        if c["n"] == "FitScale":
            c["scale"] = min(1.0, (view_h - 32) / node["size"][3])
        elif c["n"] == "RowFit":
            width = view_w - 2 * (28 + 12)
            height = view_h - 2 * 28 - 64
            c["scale"] = min(1.0, width / node["size"][1], height / node["size"][3])
            node["pos"] = [0.5, 0, 0.5, -node["size"][3] * c["scale"] / 2]
    for c in node.get("kids", []):
        refit(c, view_w, view_h)


def render(scene, size_name, size, out_dir):
    W, H = size[0] * SS, size[1] * SS
    ctx = Ctx((W, H))
    run = scene["scene"].startswith(("hud", "levelup", "pause", "death", "results", "phone_hud"))
    painter = Painter((W, H), background((W, H), scene.get("blur", 0), run))
    guis = [g for g in scene["guis"] if g.get("enabled")]
    guis.sort(key=lambda g: g.get("order", 0))
    design = COMPACT if size[1] < 500 else DESIGN  # a phone is always a touch screen
    s = max(0.55, min(1.5, min(size[0] / design[0], size[1] / design[1])))
    view_w, view_h = size[0] / s, size[1] / s
    for g in guis:
        # every ScreenGui has one Root frame scaled by Kit.Responsive: recompute it for this screen
        for root in [c for c in g.get("kids", []) if c["c"] in GUI]:
            ui = kid(root, "UIScale")
            if root["n"] == "Root" and ui:
                ui["scale"] = s
                root["size"] = [1 / s, 0, 1 / s, 0]
            refit(root, view_w, view_h)
            layout(root, 0, 0, W, H, SS)
            draw(root, painter, (0, 0, W, H), ctx)
            check_bounds(root, (W, H), ctx)
            check_overlaps(root, ctx)
    img = painter.img.convert("RGB").resize(size, Image.Resampling.LANCZOS)
    path = os.path.join(out_dir, f"{scene['scene']}_{size_name}.png")
    img.save(path, optimize=True)
    return path, ctx.issues


def main():
    src, out = sys.argv[1], sys.argv[2]
    only = set(sys.argv[3:])
    os.makedirs(out, exist_ok=True)
    total = 0
    for name in sorted(os.listdir(src)):
        if not name.endswith(".json"):
            continue
        scene_name = name[:-5]
        if only and scene_name not in only:
            continue
        scene = json.load(open(os.path.join(src, name)))
        sizes = SIZES
        if scene.get("touch"):
            sizes = {k: v for k, v in SIZES.items() if k.startswith(("phone", "tablet"))}
        for size_name, size in sizes.items():
            scene = json.load(open(os.path.join(src, name)))  # fresh copy (layout writes into it)
            path, issues = render(scene, size_name, size, out)
            uniq = sorted(set(issues))
            total += len(uniq)
            print(f"{path}: {len(uniq)} issue(s)")
            for i in uniq[:12]:
                print("   - " + i)
    print(f"done, {total} issue(s)")


if __name__ == "__main__":
    main()
