#!/usr/bin/env python3
"""Render the shared 26-destination theme set from an m3wal scheme JSON.

Usage:
    m3wal-render.py <scheme.json>

Roles from the m3wal output are mapped onto the tinct role names used by the
shared templates in ~/.config/tinct/templates (*.tmpl). The template ->
output_path mapping is read from ~/.config/tinct/templater.yaml so every
engine produces byte-consistent files for the same destinations.
"""

import os
import re
import sys

import yaml

HOME = os.path.expanduser("~")

TEMPLATER_YAML = os.path.join(HOME, ".config/tinct/templater.yaml")

# tinct role name -> m3wal scheme key. accent1-3 map to the M3 primary /
# secondary / tertiary tonal roles; onAccent4 has no direct m3wal slot, so it
# falls back to the tertiary container's on-color.
ROLE_MAP = {
    "background": "m3background",
    "foreground": "m3onBackground",
    "surface": "m3surface",
    "surfaceVariant": "m3surfaceVariant",
    "onSurface": "m3onSurface",
    "onSurfaceVariant": "m3onSurfaceVariant",
    "surfaceContainer": "m3surfaceContainer",
    "surfaceContainerLow": "m3surfaceContainerLow",
    "surfaceContainerLowest": "m3surfaceContainerLowest",
    "surfaceContainerHigh": "m3surfaceContainerHigh",
    "surfaceContainerHighest": "m3surfaceContainerHighest",
    "accent1": "m3primary",
    "onAccent1": "m3onPrimary",
    "accent1Muted": "m3primaryContainer",
    "accent2": "m3secondary",
    "onAccent2": "m3onSecondary",
    "accent2Muted": "m3secondaryContainer",
    "accent3": "m3tertiary",
    "onAccent3": "m3onTertiary",
    "accent3Muted": "m3tertiaryContainer",
    "onAccent4": "m3onTertiaryContainer",
    "danger": "m3error",
    "onDanger": "m3onError",
    "outline": "m3outline",
    "outlineVariant": "m3outlineVariant",
    "inverseSurface": "m3inverseSurface",
    "inverseOnSurface": "m3inverseOnSurface",
    "inversePrimary": "m3inversePrimary",
    "shadow": "m3shadow",
    "scrim": "m3scrim",
}

EXPR = re.compile(r"\{\{ \(get \. \"([A-Za-z0-9_]+)\"\)\.([A-Za-z]+) \}\}")


def load_scheme(path):
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def build_palette(colors):
    palette = {}
    for tinct_role, m3_key in ROLE_MAP.items():
        hexval = colors.get(m3_key)
        if not isinstance(hexval, str) or not hexval.startswith("#"):
            raise ValueError(f"missing m3wal key {m3_key} for role {tinct_role}")
        palette[tinct_role] = hexval
    return palette


def render_template(content, palette):
    def sub(m):
        role, method = m.group(1), m.group(2)
        if role not in palette:
            raise KeyError(f"unknown role {role!r} in template")
        h = palette[role].lstrip("#")
        r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
        if method == "Hex":
            return "#" + h
        if method == "HexNoHash":
            return h
        if method == "R":
            return str(r)
        if method == "G":
            return str(g)
        if method == "B":
            return str(b)
        if method == "RGBA":
            return f"rgba({r},{g},{b},1)"
        if method == "RGB":
            return f"rgb({r},{g},{b})"
        raise KeyError(f"unknown method .{method}")
    return EXPR.sub(sub, content)


def main():
    if len(sys.argv) != 2:
        print("usage: m3wal-render.py <scheme.json>", file=sys.stderr)
        return 1

    scheme = load_scheme(sys.argv[1])
    palette = build_palette(scheme.get("colors", {}))

    with open(TEMPLATER_YAML, "r", encoding="utf-8") as f:
        config = yaml.safe_load(f)

    total = ok = 0
    for entry in config.get("templates", []):
        if not entry.get("enabled", True):
            continue
        total += 1
        template_path = os.path.expanduser(entry["template_path"])
        output_path = os.path.expanduser(entry["output_path"])
        try:
            with open(template_path, "r", encoding="utf-8") as f:
                content = f.read()
            rendered = render_template(content, palette)
            parent = os.path.dirname(output_path)
            if parent:
                os.makedirs(parent, exist_ok=True)
            with open(output_path, "w", encoding="utf-8") as f:
                f.write(rendered)
            print(f"  \u2713 {output_path} ({len(rendered)} bytes)")
            ok += 1
        except Exception as e:
            print(f"  \u2717 {entry.get('name')}: {e}", file=sys.stderr)

    print(f"\n\u2713 Processed {total} template(s), {ok} written")
    return 0


if __name__ == "__main__":
    sys.exit(main())