#!/usr/bin/env python3
"""
Static check for Roblox property names that the type checker cannot see.

UI and world parts are built from tables, e.g. Kit.New("Frame", { Size = ..., Radius = 5 }).
Such keys are assigned dynamically, so a typo (or a property that does not exist on that
class) would only fail at runtime inside Roblox. This script reads the Roblox class
definitions (luau-lsp globalTypes.d.luau) and checks every key of those tables.

usage: python3 tools/check_props.py <path-to-globalTypes.d.luau> [src]
"""
import os
import re
import sys

defs_path = sys.argv[1]
src_root = sys.argv[2] if len(sys.argv) > 2 else "src"

classes = {}
parents = {}
current = None
for line in open(defs_path, encoding="utf-8"):
    m = re.match(r"^declare (?:class|extern type) (\w+)(?: extends (\w+))?", line)
    if m:
        current = m.group(1)
        classes.setdefault(current, set())
        if m.group(2):
            parents[current] = m.group(2)
        continue
    if line.startswith("end"):
        current = None
        continue
    if current:
        m = re.match(r"^\s+([A-Za-z_]\w*)\s*:", line)
        if m:
            classes[current].add(m.group(1))


def props_of(cls):
    out = set()
    while cls:
        out |= classes.get(cls, set())
        cls = parents.get(cls)
    return out


def table_keys(text, start):
    """keys at depth 1 of the table literal starting at text[start] == '{'
    (assignments inside inline function bodies are skipped)"""
    depth = 0
    block = 0  # nesting of function/if/do/repeat blocks inside the table
    keys = []
    i = start
    while i < len(text):
        c = text[i]
        if c in "\"'":
            q = c
            i += 1
            while i < len(text) and text[i] != q:
                if text[i] == "\\":
                    i += 1
                i += 1
        elif c == "-" and text[i : i + 2] == "--":
            while i < len(text) and text[i] != "\n":
                i += 1
        elif c in "{([":
            depth += 1
        elif c in "})]":
            depth -= 1
            if depth == 0:
                return keys
        elif c.isalpha() or c == "_":
            m = re.match(r"[A-Za-z_]\w*", text[i:])
            word = m.group(0)
            prev = text[i - 1] if i > 0 else " "
            if not (prev.isalnum() or prev in "_.:"):
                if word in ("function", "if", "do", "repeat"):
                    block += 1
                elif word in ("end", "until"):
                    block -= 1
                elif depth == 1 and block == 0 and re.match(r"[A-Za-z_]\w*\s*=(?!=)", text[i:]):
                    keys.append(word)
            i += len(word)
            continue
        i += 1
    return keys


BUTTON_OPTIONS = {"Text", "Color", "Dark", "Size", "Position", "AnchorPoint", "Parent", "TextSize", "Font", "Radius", "Name", "OnClick", "LayoutOrder"}
PATTERNS = [
    # regex, class (or None = taken from group 1), extra allowed keys
    (r'Kit\.New\(\s*"(\w+)"\s*,\s*\{', None, {"Parent"}),
    (r"Kit\.Label\(\s*\{", "TextLabel", {"Parent", "StrokeThickness", "StrokeColor"}),
    (r"Kit\.Panel\(\s*\{", "Frame", {"Parent", "Radius"}),
    (r"Widgets\.Scroll\(\s*[\w.\[\]\"]+\s*,\s*\{", "ScrollingFrame", set()),
    (r"\bpart\(\s*[\w.]+\s*,\s*\{", "Part", {"CanCollide", "CastShadow", "Parent"}),
]

errors = 0
checked = 0
for dirpath, _, files in os.walk(src_root):
    for name in files:
        if not name.endswith((".lua", ".luau")):
            continue
        path = os.path.join(dirpath, name)
        text = open(path, encoding="utf-8").read()
        for pattern, fixed, extra in PATTERNS:
            for m in re.finditer(pattern, text):
                cls = fixed or m.group(1)
                if cls not in classes:
                    print(f"{path}: unknown class {cls}")
                    errors += 1
                    continue
                allowed = props_of(cls) | extra
                for key in table_keys(text, m.end() - 1):
                    checked += 1
                    if key not in allowed:
                        line = text.count("\n", 0, m.start()) + 1
                        print(f"{path}:{line}: '{key}' is not a property of {cls}")
                        errors += 1
        for m in re.finditer(r"Kit\.Button\(\s*\{", text):
            for key in table_keys(text, m.end() - 1):
                checked += 1
                if key not in BUTTON_OPTIONS:
                    line = text.count("\n", 0, m.start()) + 1
                    print(f"{path}:{line}: '{key}' is not a Kit.Button option")
                    errors += 1
        # ball(parent, pos, size, color, { props }) and cylinder(parent, a, b, d, color, { props })
        for m in re.finditer(r"\b(ball|cylinder)\(", text):
            depth, i, commas, start = 0, m.end() - 1, 0, None
            while i < len(text):
                c = text[i]
                if c in "({[":
                    depth += 1
                    if c == "{" and depth == 2 and commas == (4 if m.group(1) == "ball" else 5):
                        start = i
                        break
                elif c in ")}]":
                    depth -= 1
                    if depth == 0:
                        break
                elif c == "," and depth == 1:
                    commas += 1
                i += 1
            if start is not None:
                allowed = props_of("Part")
                for key in table_keys(text, start):
                    checked += 1
                    if key not in allowed:
                        line = text.count("\n", 0, m.start()) + 1
                        print(f"{path}:{line}: '{key}' is not a property of Part")
                        errors += 1

print(f"checked {checked} property keys, {errors} problem(s)")
sys.exit(1 if errors else 0)
