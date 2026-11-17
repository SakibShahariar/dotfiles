#!/usr/bin/env python3
"""Batch-assign wallpapers to matugen themes by palette match.

Wallpapers are indexed once (hue histogram + luminance), then every theme is
scored against that cache, so adding theme #596 costs milliseconds, not a
fresh image scan.

Usage:
    assign-wallpapers.py --index              # build/refresh the image cache
    assign-wallpapers.py --report             # dry run: show what would change
    assign-wallpapers.py --write              # append assignments to the map
    assign-wallpapers.py --write --overwrite  # also replace existing entries
    assign-wallpapers.py --write --only vhs vaporwave
"""

import argparse
import colorsys
import json
import math
import os
import re
import shutil
import sys
import time
from pathlib import Path

HOME = Path.home()
THEMES_DIR = HOME / ".config/matugen/themes"
MAP_FILE = HOME / ".config/matugen/wallpaper_map.json"
INDEX_FILE = HOME / ".cache/matugen/wallpaper_index.json"
WALLPAPER_DIR = Path("/mnt/Storage/Wallpapers")

BINS = 36  # 10 degrees per bin
PER_THEME = 4
LOW_CONFIDENCE = 0.30

VARIANT_RE = re.compile(
    r'^(.*)-(dark-high-contrast|light-high-contrast|amoled|dark|light)$',
    re.IGNORECASE)


# ---------------------------------------------------------------- index
def hue_bin(h):
    return min(BINS - 1, int(h * BINS) % BINS)


def build_index(force=False):
    if INDEX_FILE.exists() and not force:
        idx = json.loads(INDEX_FILE.read_text())
        known = {p.name for p in WALLPAPER_DIR.iterdir() if p.suffix.lower() in (".jpg", ".jpeg", ".png")}
        if set(idx.get("images", {})) == known:
            return idx

    from PIL import Image  # imported lazily so --report works without Pillow

    images = {}
    files = sorted(p for p in WALLPAPER_DIR.iterdir()
                   if p.suffix.lower() in (".jpg", ".jpeg", ".png"))
    for i, path in enumerate(files, 1):
        try:
            im = Image.open(path).convert("RGB")
            im.thumbnail((80, 80))
            px = list(im.getdata())
        except Exception:
            continue
        hist = [0.0] * BINS
        lum = pink = cyan = 0.0
        n = len(px) or 1
        for r, g, b in px:
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            lum += 0.2126 * r + 0.7152 * g + 0.0722 * b
            if s > 0.12 and v > 0.10:
                hist[hue_bin(h)] += s * v
            deg = h * 360
            if 270 <= deg <= 345 and s > 0.30 and v > 0.20:
                pink += 1
            elif 160 <= deg <= 205 and s > 0.30 and v > 0.20:
                cyan += 1
        images[path.name] = {
            "lum": round(lum / n / 255, 4),
            "hue": [round(x, 4) for x in hist],
            "pink": round(pink / n, 4),
            "cyan": round(cyan / n, 4),
        }
        if i % 100 == 0:
            print(f"  indexed {i}/{len(files)}", file=sys.stderr)

    idx = {"version": 1, "dir": str(WALLPAPER_DIR), "images": images}
    INDEX_FILE.parent.mkdir(parents=True, exist_ok=True)
    INDEX_FILE.write_text(json.dumps(idx))
    return idx


# ---------------------------------------------------------------- palette
def color_of(data, role):
    node = data.get("colors", {}).get(role)
    if isinstance(node, str):
        return node
    if isinstance(node, dict):
        default = node.get("default")
        if isinstance(default, str):
            return default
        if isinstance(default, dict) and isinstance(default.get("color"), str):
            return default["color"]
        if isinstance(node.get("color"), str):
            return node["color"]
    return None


def hex_to_hsv(hex_color):
    h = hex_color.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return colorsys.rgb_to_hsv(r, g, b)


def theme_vector(data):
    """Weighted hue histogram for the theme's accent colours."""
    vec = [0.0] * BINS
    roles = (("primary", 1.0), ("secondary", 0.55), ("tertiary", 0.30))
    for role, weight in roles:
        hexc = color_of(data, role)
        if not hexc:
            continue
        h, s, v = hex_to_hsv(hexc)
        if s < 0.10:
            continue
        w = weight * s * max(v, 0.2)
        b = hue_bin(h)
        vec[b] += w
        vec[(b + 1) % BINS] += w * 0.35
        vec[(b - 1) % BINS] += w * 0.35
    norm = math.sqrt(sum(x * x for x in vec))
    if norm:
        vec = [x / norm for x in vec]
    return vec


def background_lum(data):
    hexc = color_of(data, "background") or color_of(data, "surface")
    if not hexc:
        return 0.15
    _h, _s, v = hex_to_hsv(hexc)
    return v


def cosine(a, b):
    if not a or not b:
        return 0.0
    return sum(x * y for x, y in zip(a, b))  # both unit-normalised


# ---------------------------------------------------------------- themes
def theme_names():
    """One key per theme file: the switcher passes exact stems.

    apply-theme.fish looks up the exact stem first (then the family), so
    per-variant entries give darker/lighter variants their own matching
    wallpapers instead of sharing a single family pick.
    """
    return {f.stem: [f] for f in sorted(THEMES_DIR.glob("*.json"))}


def load_json(path):
    try:
        return json.loads(path.read_text())
    except Exception:
        return None


def pick(group, mode):
    """Pick the variant file the switcher would prefer for this mode."""
    want = "dark" if mode == "dark" else "light"
    scored = []
    for f in group:
        stem = f.stem.lower()
        exact = stem.endswith("-" + want)
        hc = "high-contrast" in stem
        amoled = stem.endswith("-amoled")
        scored.append((0 if exact else 1 if amoled else 2, hc, f))
    scored.sort(key=lambda t: (t[0], t[1]))
    return scored[0][2]


# ---------------------------------------------------------------- scoring
def dominant_hue(hist):
    """Circular mean of a wallpaper's hue histogram -> (degrees, strength)."""
    total = sum(hist) or 1.0
    x = sum(w * math.cos(i * 2 * math.pi / BINS)
            for i, w in enumerate(hist)) / total
    y = sum(w * math.sin(i * 2 * math.pi / BINS)
            for i, w in enumerate(hist)) / total
    return math.degrees(math.atan2(y, x)) % 360, math.hypot(x, y)


def precompute(index):
    """Unit-normalise every wallpaper hue vector once."""
    feats = []
    for name, feat in index["images"].items():
        vec = feat["hue"]
        norm = math.sqrt(sum(x * x for x in vec)) or 1.0
        dom, strength = dominant_hue(vec)
        feats.append((name, [x / norm for x in vec], feat["lum"], dom, strength))
    return feats


def assign_for(theme_vec, theme_hue, theme_sat, bg_lum, feats, taken, usage=None):
    # Hard content constraints: a light theme gets a bright wallpaper and a
    # dark/amoled theme gets a dark one.  Hue must be in the same family
    # unless either colour is near-neutral (where hue is meaningless).
    dark = bg_lum < 0.5
    bright_ok = (lambda l: l < 0.45) if dark else (lambda l: l > 0.45)
    hue_ok = (lambda dom, strength: strength < 0.25 or theme_sat < 0.15
              or min(abs(dom - theme_hue) % 360,
                     360 - abs(dom - theme_hue) % 360) <= 60)
    cand = [f for f in feats if bright_ok(f[2]) and hue_ok(f[3], f[4])]
    if len(cand) < PER_THEME:            # too few in that colour family
        cand = [f for f in feats if bright_ok(f[2])]
    if len(cand) < PER_THEME:            # last resort: brightness wins
        cand = feats

    target = 0.30 if dark else 0.55
    usage = usage or {}
    picks = []
    for name, unit, lum, _dom, _strength in cand:
        sim = cosine(unit, theme_vec) if theme_vec else 0.0
        fit = 1.0 - min(1.0, abs(lum - target) / 0.45)
        # spread the library out: reuse costs score, so 400 themes don't all
        # land on the same three magenta wallpapers
        raw = 0.8 * sim + 0.2 * fit
        score = raw - 0.035 * usage.get(name, 0)
        picks.append((score, name, unit, lum, raw))

    picks.sort(key=lambda t: -t[0])
    chosen = []
    for score, name, unit, lum, raw in picks:
        if name in taken:
            continue
        # keep the set visually varied: no near-identical hue + brightness
        if any(cosine(unit, c_unit) > 0.985 and abs(lum - c_lum) < 0.05
               for _s, _n, c_unit, c_lum, _r in chosen):
            continue
        chosen.append((score, name, unit, lum, raw))
        if len(chosen) >= PER_THEME:
            break
    return chosen


# ---------------------------------------------------------------- map write
def insert_entries(entries):
    """Append entries to the hand-formatted map without reformatting it."""
    text = MAP_FILE.read_text()
    end = text.rstrip().rfind("}")
    head = text[:end].rstrip()
    if head.endswith("{"):
        head = head  # empty object: no trailing comma
    elif not head.endswith(","):
        head += ","
    blocks = []
    for name, paths in entries:
        lines = ",\n".join(f'      "{p}"' for p in paths)
        blocks.append(f'  "{name}": {{\n    "wallpapers": [\n{lines}\n    ]\n  }}')
    body = ",\n\n".join(blocks)
    new = head + "\n\n" + body + "\n}\n"
    json.loads(new)  # never write invalid JSON
    backup = MAP_FILE.with_suffix(".json.bak")
    shutil.copy2(MAP_FILE, backup)
    MAP_FILE.write_text(new)
    return backup


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--index", action="store_true", help="rebuild the wallpaper cache")
    ap.add_argument("--report", action="store_true", help="dry run, print planned assignments")
    ap.add_argument("--write", action="store_true", help="append assignments to the map")
    ap.add_argument("--overwrite", action="store_true", help="replace existing entries too")
    ap.add_argument("--only", nargs="*", default=None, help="limit to these theme names")
    ap.add_argument("--mode", choices=["dark", "light"], default="dark")
    args = ap.parse_args()

    t0 = time.time()
    if args.index:
        idx = build_index(force=True)
        print(f"Indexed {len(idx['images'])} wallpapers in {time.time() - t0:.1f}s -> {INDEX_FILE}")
        return

    idx = build_index()
    feats = precompute(idx)
    groups = theme_names()
    mapping = json.loads(MAP_FILE.read_text()) if MAP_FILE.exists() else {}

    wanted = set(args.only) if args.only else set(groups)
    planned, skipped, low = [], 0, []
    usage = {}
    for name in sorted(wanted, key=str.lower):
        group = groups.get(name)
        if not group:
            continue
        if name in mapping and not args.overwrite:
            skipped += 1
            continue
        data = load_json(pick(group, args.mode))
        if not data:
            continue
        vec = theme_vector(data)
        bg = background_lum(data)
        primary = color_of(data, "primary")
        ph, ps, _pv = hex_to_hsv(primary) if primary else (0, 0, 0)
        picks = assign_for(vec, ph * 360, ps, bg, feats,
                           set(mapping.get(name, {}).get("wallpapers", [])), usage)
        if not picks:
            continue
        paths = [str(WALLPAPER_DIR / p[1]) for p in picks]
        for _score, img, _u, _l, _raw in picks:
            usage[img] = usage.get(img, 0) + 1
        planned.append((name, paths))
        if picks[0][4] < LOW_CONFIDENCE:
            low.append((name, round(picks[0][4], 3), paths[0]))

    print(f"themes on disk (grouped like the switcher): {len(groups)}")
    print(f"already mapped, left alone:                 {skipped}")
    print(f"newly assigned:                             {len(planned)}")
    print(f"low-confidence (<{LOW_CONFIDENCE}):                      {len(low)}")
    if planned:
        print(f"distinct lead wallpapers used:              "
              f"{len({p[0] for _, p in planned})} of {len(planned)} themes")
    if planned:
        print("\nsample:")
        for name, paths in planned[:8]:
            print(f"  {name:28} {os.path.basename(paths[0])}")
    if low:
        print("\nneeds a human:")
        for name, score, first in low[:10]:
            print(f"  {name:28} score={score}  {os.path.basename(first)}")

    if args.write and planned:
        backup = insert_entries(planned)
        print(f"\nwrote {len(planned)} entries to {MAP_FILE} (backup: {backup})")
    elif planned:
        print("\ndry run — pass --write to update wallpaper_map.json")
    print(f"\ntotal {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()
