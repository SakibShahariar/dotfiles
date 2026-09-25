#!/usr/bin/env python3
"""Convert matugen templates to tinct templater templates.

matugen placeholder:  {{ colors.<role>.default.<fmt> }}
tinct placeholder:    {{ (get . "<tinct_role>").<Method> }}

Emits Go-template files (tinct method syntax, verified against the
tinct-plugin-templater 0.5.0 function map: get/has/themeType/seq/ansi/rgbSpaces).
"""
import pathlib
import re

SRC = pathlib.Path.home() / ".config" / "matugen" / "templates"
DST = pathlib.Path.home() / ".config" / "tinct" / "templates"

ROLE_MAP = {
    # core
    "background": "background",
    "on_background": "foreground",
    "surface": "surface",
    "surface_dim": "surfaceContainerLowest",
    "surface_bright": "surfaceContainerHighest",
    "surface_variant": "surfaceVariant",
    "on_surface": "onSurface",
    "on_surface_variant": "onSurfaceVariant",
    "surface_container": "surfaceContainer",
    "surface_container_low": "surfaceContainerLow",
    "surface_container_lowest": "surfaceContainerLowest",
    "surface_container_high": "surfaceContainerHigh",
    "surface_container_highest": "surfaceContainerHighest",
    "surface_tint": "accent1",
    "source_color": "accent1",
    # primary = accent1
    "primary": "accent1",
    "on_primary": "onAccent1",
    "primary_container": "accent1Muted",
    "on_primary_container": "onAccent1",
    "primary_fixed": "accent1",
    "on_primary_fixed": "onAccent1",
    "primary_fixed_dim": "accent1Muted",
    "on_primary_fixed_variant": "onAccent2",
    # secondary = accent2
    "secondary": "accent2",
    "on_secondary": "onAccent2",
    "secondary_container": "accent2Muted",
    "on_secondary_container": "onAccent2",
    "secondary_fixed": "accent2",
    "on_secondary_fixed": "onAccent2",
    "secondary_fixed_dim": "accent2Muted",
    "on_secondary_fixed_variant": "onAccent3",
    # tertiary = accent3
    "tertiary": "accent3",
    "on_tertiary": "onAccent3",
    "tertiary_container": "accent3Muted",
    "on_tertiary_container": "onAccent3",
    "tertiary_fixed": "accent3",
    "on_tertiary_fixed": "onAccent3",
    "tertiary_fixed_dim": "accent3Muted",
    "on_tertiary_fixed_variant": "onAccent4",
    # error  = danger
    "error": "danger",
    "on_error": "onDanger",
    "error_container": "surfaceContainerHigh",
    "on_error_container": "onSurfaceVariant",
    # misc
    "outline": "outline",
    "outline_variant": "outlineVariant",
    "inverse_surface": "inverseSurface",
    "inverse_on_surface": "inverseOnSurface",
    "inverse_primary": "inversePrimary",
    "scrim": "scrim",
    "shadow": "shadow",
}

FORMAT_MAP = {
    "hex": "Hex",
    "hex_stripped": "HexNoHash",
    "rgba": "RGBA",
    "rgb": "RGB",
    "red": "R",
    "green": "G",
    "blue": "B",
}

LEAK = re.compile(
    r"\{\{\s*colors\.([a-z0-9_]+)\.default\.(hex|hex_stripped|rgba|rgb|red|green|blue)"
    r"(?:\s*\|\s*auto_lightness:\s*[0-9.]+)?\s*\}\}"
)
OTHER = re.compile(r"\{\{[^}]*\{\{|[{}][{}][^}]")
TARGETS = [
    "btop.theme",
    "cava-colors.ini",
    "clock-rs-conf.toml",
    "mpv-config.conf",
    "fish.tpl",
    "fresh.json",
    "gnome-shell.css",
    "gnome-active-layout.css",
    "gtk3-colors.css",
    "gtk4-colors.css",
    "kew.theme",
    "kitty.conf",
    "kvantum-colors.kvconfig",
    "kvantum-colors.svg",
    "mpv-uosc.conf",
    "colors.json",
    "qtct-colors.conf",
    "starship.toml",
    "clock-color.css",
    "search-light.css",
    "yazi.toml",
    "zen-userchrome.css",
    "zen-usercontent.css",
]


def convert(src_name: str) -> tuple[str, list[str]]:
    src = SRC / src_name
    text = src.read_text()
    seen = set()
    misses = set()

    def repl(m):
        role, fmt = m.group(1), m.group(2)
        seen.add((role, fmt))
        trole = ROLE_MAP.get(role)
        if trole is None:
            misses.add(role)
            return m.group(0)
        return "{{ (get . \"%s\").%s }}" % (trole, FORMAT_MAP[fmt])

    out = LEAK.sub(repl, text)
    rest = OTHER.findall(out)
    return out, sorted(seen), sorted(misses), rest


def main():
    DST.mkdir(parents=True, exist_ok=True)
    total = 0
    for name in TARGETS:
        out, seen, misses, rest = convert(name)
        if misses:
            print(f"[WARN] {name}: unmapped roles {misses}")
        if rest:
            print(f"[WARN] {name}: leftover braces {rest[:5]}")
        dst = DST / (name + ".tmpl")
        dst.write_text(out)
        n = len(seen)
        total += n
        print(f"{name}: {n} placeholders -> {dst.name}")
    print(f"total converted: {total}")


if __name__ == "__main__":
    main()