#!/usr/bin/env python3
"""
Materialicious duotone icon generator
====================================

Generates the Material-Grad theme: a duotone re-paint of Material-Solo's
flat accent app icons, in the style of Omarchy's `icon-mono.sh`: instead of
painting every app icon one flat accent colour, each icon keeps its internal
light/dark structure and that structure is remapped onto a two-colour ramp.

The source is a flat monochrome SVG set. For every distinct fill/stroke
colour in the SVG we compute its relative luminance (Rec.709) and remap it
onto dark -> (accent) -> light, where:

  dark  = ink / deep tone  (the panel frame colour, kept in the palette)
  light = accent           (what the dock/theme foreground should carry)

Black artwork (shadows, outlines) lands on `dark`; white/highlights land on
`light`; mid tones spread between them through an S-curve, so a red/green/blue
logo becomes a tonal sculpture of the palette instead of a flat stamp.

Output is written next to the input as `<name>.mono.svg` (or into --outdir),
and the coat of original colours is never modified.

USAGE
-----
    mono-icons.py --dark #000000 --light #c9bfff [--radius 0.5]
                   [--outdir dir] svg1 [svg2 ...]

    mono-icons.py --dark #1a2733 --light #c9bfff --out ./Material-Mono/apps/scalable \
        apps/scalable/org.gnome.Nautilus.svg apps/scalable/firefox.svg

Colour mapping
--------------
    lum = 0.2126 R + 0.7152 G + 0.0722 B      (linear, but on the sRGB value
                                              so it matches human-perceived
                                              "how light is this swatch")
    t   = smoothstep(0, 1, (lum - dark_lum) / (1 - dark_lum))   # 0..1
    t   = s_curve(t)         # sharpen the body/detail boundary
    out = lerp(dark, light, t)

`--radius` (default 0.5) controls the S-curve knee: 0 = linear ramp,
larger = more contrast between body and detail. Values 0.3..0.7 look best.

Only `#rrggbb`, `#rgb` (expanded to `#rrggbb`) and `rgb(r,g,b)` fills/strokes
are remapped, plus gradient `stop-color`s (style or attribute form) so
gradient-bearing artwork is recolored onto the ramp too instead of leaking
the source palette. `currentColor` and `url(#...)` layer refs are left as-is,
but the gradient <stop> colors they resolve to are remapped.

`--autoscale` (recommended): instead of mapping every icon onto the same
global dark/light scale, each icon's brightest colour is stretched to the
light end and its darkest to the dark end. This keeps foreground/background
contrast consistent across icons even when the source art is all-mid-tone
(e.g. a white glyph on a light-blue Telegram circle). Without it, those two
tones collapse together near the light end.
"""

import argparse
import os
import re
import sys

COLOR_RE = re.compile(
    r"(?i)(fill|stroke|stop-color):\s*(#[0-9a-f]{6}|#[0-9a-f]{3}|rgb\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*\))"
    r"|(?:\b(fill|stroke|stop-color)=)\"(#[0-9a-f]{6}|#[0-9a-f]{3}|rgb\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*\))\"",
)

# A shape element whose tag carries no fill or stroke at all: give its
# (black-default) rendering an explicit ink fill so the ramp can own it.
SHAPE_TAG_RE = re.compile(
    r"(?i)<((?:path|rect|circle|ellipse|polygon|polyline)\b[^>]*?)(/?>)",
)

SVG_RE = re.compile(r"(?i)<svg\b[^>]*>")
TAG_RE = re.compile(r"(?i)<(/?)svg\b")


def hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    if len(h) == 3:
        return (int(h[0], 16) * 17, int(h[1], 16) * 17, int(h[2], 16) * 17)
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def rgb_to_hex(r: int, g: int, b: int) -> str:
    return "#%02x%02x%02x" % (r, g, b)


def rgb_str(rgb: str) -> tuple[int, int, int]:
    m = re.match(r"rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)", rgb)
    return int(m.group(1)), int(m.group(2)), int(m.group(3))


def luminance(r: int, g: int, b: int) -> float:
    # Perceived luminance on the sRGB gamma-encoded values; good enough to
    # rank "dark vs light" swatches inside a logo.
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def smoothstep(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def s_curve(t: float, radius: float) -> float:
    # Sigmoid around 0.5 -> compresses the mid band, pushes tones toward the
    # dark or light end (same spirit as Omarchy's -sigmoidal-contrast 4x50%).
    t = max(0.0, min(1.0, t))
    # Sigmoid through (0.5, 0.5): t' = 1/(1+exp(-k*(t-0.5))), k from radius.
    k = 4.0 * radius * 10.0 / (1.0 + 4.0 * radius)
    import math

    return 1.0 / (1.0 + math.exp(-k * (t - 0.5)))


def piecewise_raster(lum: float, table: list[tuple[float, float]]) -> float:
    """Piecewise-linear luminance -> ramp-position lookup.

    `table` is a list of (source_luminance, ramp_t) sorted by luminance.
    Source tone outside the table clamps to the nearest endpoint.
    """
    if not table:
        return lum
    lo_lum, lo_t = table[0]
    hi_lum, hi_t = table[-1]
    if lum <= lo_lum:
        return lo_t
    if lum >= hi_lum:
        return hi_t
    for (l1, t1), (l2, t2) in zip(table, table[1:]):
        if l1 <= lum <= l2:
            frac = (lum - l1) / (l2 - l1) if l2 > l1 else 0.0
            return t1 + (t2 - t1) * frac
    return hi_t


def build_ramp(dark, light, radius, autoscale=False, src_min=0.0, src_max=1.0,
               linear=False, min_t=0.0, max_t=1.0, invert=False,
               piecewise=None):
    dark_rgb = hex_to_rgb(dark)
    light_rgb = hex_to_rgb(light)
    dark_lum = luminance(*dark_rgb) / 255.0
    light_lum = luminance(*light_rgb) / 255.0
    global_span = light_lum - dark_lum or 1.0

    # Per-icon: stretch the source's own tone range across the ramp so the
    # darkest and brightest tones in THIS icon land on the dark/light ends
    # (telegram's light-blue circle + white plane no longer collapse together).
    src_span = src_max - src_min or 1.0

    def ramp(r, g, b):
        lum = luminance(r, g, b) / 255.0
        if piecewise is not None:
            # Hand-tuned luminance -> ramp-position table for sources whose
            # dominant body tone would be blown to accent (or sunk to ink) by
            # the generic s-curve (e.g. flat single-colour logos). The table
            # lists ascending luminance breakpoints with the ramp position to
            # land there; positions between breakpoints are interpolated.
            t = piecewise_raster(lum, piecewise)
            if min_t or max_t < 1.0:
                t = min_t + (max_t - min_t) * t
            return tuple(
                round(dark_rgb[i] + (light_rgb[i] - dark_rgb[i]) * t)
                for i in range(3)
            )
        if invert:
            # Invert path: pure source-tone normalization (the icon's own
            # darkest/brightest fills sit at the ramp ends regardless of the
            # accent ink/light window), then swap dark/light roles so a white
            # paper (source light) becomes the ink body and the dark pencil
            # strokes become the accent highlight. A hard sigmoid (through
            # ~0.45) re-spreads the inverted tones so both the page body and
            # the pencil accents keep contrast instead of flattening to
            # midtones.
            t = (lum - src_min) / src_span
            t = 1.0 - t
            import math
            t = 1.0 / (1.0 + math.exp(-9.0 * (t - 0.45)))
        else:
            t = (lum - dark_lum) / global_span
            if autoscale:
                t = (t - src_min) / src_span
            if linear:
                t = max(0.0, min(1.0, t))
            else:
                t = s_curve(t, radius)
        # Clamp into [min_t, max_t]: keeps the darkest ramp position above
        # near-black and the lightest below full accent where a flat or
        # dark-dominant icon needs a body instead of blown-out highlights.
        if min_t or max_t < 1.0:
            t = min_t + (max_t - min_t) * t
        return tuple(
            round(dark_rgb[i] + (light_rgb[i] - dark_rgb[i]) * t) for i in range(3)
        )

    return ramp


def extract_colors(content: str) -> list[tuple[int, int, int]]:
    colors = []
    for m in COLOR_RE.finditer(content):
        if m.group(1) is not None:
            val = m.group(2)
        else:
            val = m.group(4)
        if val.startswith("#"):
            r, g, b = hex_to_rgb(val)
        else:
            r, g, b = rgb_str(val)
        colors.append((r, g, b))
    return colors


PROTECTED_RE = re.compile(
    r"(?is)<(defs|mask|clipPath|pattern|marker|symbol)\b.*?</\1>",
)

# A shape element whose tag carries no fill or stroke at all: give its
# (black-default) rendering an explicit ink fill so the ramp can own it.
SHAPE_TAG_RE = re.compile(
    r"(?i)<((?:path|rect|circle|ellipse|polygon|polyline)\b[^>]*?)(/?>)",
)


def inject_default_fill(content: str) -> str:
    # SVG default fill is black; shape elements that carry an opacity (or
    # nothing) without an explicit fill/stroke would render as ink-black
    # regardless of the ramp. Give them an explicit black so the ramp
    # recolors them like any other source tone. Shapes inside <defs>/<mask>/
    # <clipPath>/<pattern>/<marker>/<symbol> are left alone, and anything
    # that already sets fill or stroke (attribute or style) is skipped.
    def repl(m):
        body, closer = m.group(1), m.group(2)
        if re.search(r"\bfill\b", body) or re.search(r"\bstroke\b", body):
            return m.group(0)  # already colours the shape explicitly
        return f"<{body} fill=\"#000000\"{closer}"

    protected: list[str] = []
    def stash(m):
        protected.append(m.group(0))
        return f"@@PROTECT{len(protected) - 1}@@"
    stashed = PROTECTED_RE.sub(stash, content)
    injected = SHAPE_TAG_RE.sub(repl, stashed)
    for i, block in enumerate(protected):
        injected = injected.replace(f"@@PROTECT{i}@@", block)
    return injected


def recolor_content(content: str, ramp) -> tuple[str, int]:
    def repl(m):
        if m.group(1) is not None:
            prop, val = m.group(1), m.group(2)
        else:
            prop, val = m.group(3), m.group(4)
        if val.startswith("#"):
            r, g, b = hex_to_rgb(val)
        else:
            r, g, b = rgb_str(val)
        out = rgb_to_hex(*ramp(r, g, b))
        if m.group(1) is not None:
            return f"{prop}:{out}"
        else:
            return f'{prop}="{out}"'

    new, n = COLOR_RE.subn(repl, inject_default_fill(content))
    return new, n


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dark", default="#000000", help="dark end of the ramp (ink)")
    ap.add_argument("--light", default="#c9bfff", help="light end of the ramp (accent)")
    ap.add_argument("--radius", type=float, default=0.5, help="S-curve knee (0..1)")
    ap.add_argument("--autoscale", action="store_true",
                    help="stretch each icon's own tone range onto the ramp")
    ap.add_argument("--linear", action="store_true",
                    help="map tones proportionally without re-sharpening "
                         "(for re-colouring an existing duotone icon)")
    ap.add_argument("--outdir", default=None, help="write <name>.mono.svg here")
    ap.add_argument("--min-t", type=float, default=0.0,
                    help="floor tone: final t = min_t + (1-min_t)*t  (raise the "
                         "darkest end; 0.25 keeps no pixel below ~25%% of ramp)")
    ap.add_argument("--max-t", type=float, default=1.0,
                    help="ceiling tone: t lands in [min_t, max_t] instead of "
                         "[min_t, 1.0]; 0.62 caps the lightest end so a page "
                         "reads as a body instead of blown-out accent")
    ap.add_argument("--invert", action="store_true",
                    help="swap dark/light roles (white paper -> ink body, dark "
                         "pencil -> accent) for light-dominant artwork")
    ap.add_argument("--piecewise", default=None, metavar="SPEC",
                    help="hand-tuned luminance->ramp table as LUM:T,LUM:T,... "
                         "(ascending source luminance with the ramp position to "
                         "land there; interpolated between, clamped outside). "
                         "Use for flat single-colour sources whose body tone "
                         "would otherwise be blown to accent or sunk to ink.")
    ap.add_argument("svgs", nargs="*", help="source SVG files (optional with --jobs)")
    ap.add_argument("--jobs", default=None, metavar="FILE",
                    help="batch mode: process many icons in ONE interpreter "
                         "(avoids 60+ Python startups). Each line is "
                         "<src-svg>\\t<space-separated extra flags>, e.g.\n"
                         "  /p/sources/a.svg\\t--invert --min-t 0.30\n"
                         "Ramp args (--dark/--light/--radius/--autoscale) come "
                         "from the CLI and apply to every job.")
    args = ap.parse_args()

    if not (args.dark.startswith("#") and args.light.startswith("#")):
        print("mono-icons: dark/light must be #rrggbb", file=sys.stderr)
        return 2

    def run_job(src, extra: list):
        content = open(src, encoding="utf-8", errors="ignore").read()
        src_min, src_max = 0.0, 1.0
        if args.autoscale:
            try:
                colors = extract_colors(content)
                lums = [luminance(r, g, b) / 255.0 for r, g, b in colors]
                # Only stretch when the source actually spans several tones.
                # A near-flat icon (one dominant colour) must keep its natural
                # luminance position on the ramp instead of collapsing to the
                # dark end or the light end.
                if max(lums) - min(lums) > 0.03:
                    src_min, src_max = min(lums), max(lums)
            except ValueError:
                pass
        piecewise = None
        if args.piecewise:
            spec = args.piecewise
            piecewise = []
            for pair in spec.split(","):
                lum, t = pair.split(":")
                piecewise.append((float(lum), float(t)))
            piecewise.sort()
        ramp = build_ramp(args.dark, args.light, args.radius,
                          autoscale=args.autoscale, src_min=src_min, src_max=src_max,
                          linear=args.linear,
                          min_t=args.min_t, max_t=args.max_t, invert=args.invert,
                          piecewise=piecewise)
        new, n = recolor_content(content, ramp)
        if n == 0:
            print(f"mono-icons: skip (no #rrggbb/rgb() colours): {src}", file=sys.stderr)
            return 1
        out_dir = args.outdir or os.path.dirname(src)
        os.makedirs(out_dir, exist_ok=True)
        base = os.path.splitext(os.path.basename(src))[0]
        out = os.path.join(out_dir, f"{base}.mono.svg")
        open(out, "w", encoding="utf-8").write(new)
        print(f"{src} -> {out}   ({n} colours remapped)")
        return 0

    # --jobs batched mode: one interpreter for all icons.
    if args.jobs:
        n_fail = 0
        with open(args.jobs, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split("\t", 1)
                src, flags = parts[0], parts[1] if len(parts) > 1 else ""
                # Reset per-job mutable ramp args to their CLI defaults.
                args.invert = False
                args.min_t = 0.0
                args.max_t = 1.0
                args.piecewise = None
                extra = []
                # Per-job overrides survive in either CLI form ("--min-t 0.30")
                # or the compact jobs form ("min-t 0.30"): dash is optional.
                if re.search(r"(^|[\s-])(--?)?invert(\s|$)", flags):
                    args.invert = True
                if re.search(r"(^|[\s-])(--?)?autoscale(\s|$)", flags):
                    args.autoscale = True
                m = re.search(r"-?min-t\s+([0-9.]+)", flags)
                if m:
                    args.min_t = float(m.group(1))
                m = re.search(r"-?max-t\s+([0-9.]+)", flags)
                if m:
                    args.max_t = float(m.group(1))
                m = re.search(r"-?piecewise\s+([0-9.:,]+)", flags)
                if m:
                    args.piecewise = m.group(1)  # run_job reads extra below
                if args.piecewise:
                    extra.append("--piecewise")
                    extra.append(args.piecewise)
                if not os.path.isfile(src):
                    print(f"mono-icons: skip (missing): {src}", file=sys.stderr)
                    continue
                if run_job(src, extra):
                    n_fail += 1
        return 0 if n_fail == 0 else 1

    if not os.path.isfile(args.svgs[0]) and os.path.isdir(args.svgs[0]):
        print("mono-icons: pass SVG files, not a directory", file=sys.stderr)
        return 2
    if not any(os.path.isfile(s) for s in args.svgs):
        print(f"mono-icons: no input files found", file=sys.stderr)
        return 2

    n_fail = 0
    for src in args.svgs:
        if not os.path.isfile(src):
            print(f"mono-icons: skip (missing): {src}", file=sys.stderr)
            continue
        if run_job(src, []):
            n_fail += 1
    return 0 if n_fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())