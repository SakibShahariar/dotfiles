#!/usr/bin/env python3
"""Convert matugen templates to hellwal templates.

Reads every template referenced by matugen's config.toml output set and
rewrites its Tera-style Material placeholders

    {{ colors.<role>.default.<fmt> [| auto_lightness: 30.0] }}

into hellwal `%% ... %%` expressions built from a single role-mapping table.
Material Design tonal roles do not exist in hellwal's 16-color model, so every
role is *derived* from a base plot color (color0-15) plus hellwal color ops.

Run:
    python3 ~/.config/hellwal/tools/convert-matugen.py

Output lands in ~/.config/hellwal/templates/ (same filenames as matugen) plus a
hand-rolled hellwal-colors.css that mirrors matugen-colors.css' CSS-variable
format, which the hellwal.fish pipeline reads.
"""

import os
import re

SRC = os.path.expanduser("~/.config/matugen/templates")
DST = os.path.expanduser("~/.config/hellwal/templates")

# ---------------------------------------------------------------------------
# Role mapping: Material tonal roles -> hellwal color expression
# Base plot colors: color0/background (darkest), color15/foreground (lightest),
# color13 = bright accent, color6 = secondary accent, color5 = tertiary,
# color1 = red band (error). Chains apply left-to-right in hellwal.
# ---------------------------------------------------------------------------
ROLES = {
    "background":                 "color0",
    "on_background":              "color0.lighten(0.1).invert().desaturate(0.65)",
    "surface":                    "color0",
    "surface_dim":                "color0",
    "surface_bright":             "color0.lighten(0.18)",
    "surface_variant":            "color15.darken(0.55).desaturate(0.5)",
    "on_surface":                 "color0.lighten(0.1).invert().desaturate(0.6)",
    "on_surface_variant":         "color0.lighten(0.1).invert().desaturate(0.78)",
    "surface_container_lowest":   "color0",
    "surface_container_low":      "color0.lighten(0.04)",
    "surface_container":          "color0.lighten(0.08)",
    "surface_container_high":     "color0.lighten(0.12)",
    "surface_container_highest":  "color0.lighten(0.16)",
    "surface_tint":               "color13",
    "primary":                    "color13",
    "on_primary":                 "color13.darken(0.48).desaturate(0.8)",
    "primary_container":          "color13.darken(0.22)",
    "on_primary_container":       "color13.lighten(0.32)",
    "primary_fixed":              "color13.lighten(0.22)",
    "primary_fixed_dim":          "color13.lighten(0.08)",
    "on_primary_fixed":           "color13.darken(0.4)",
    "on_primary_fixed_variant":   "color13.darken(0.26)",
    # Secondary/tertiary are hew-rotated from their luminance slots so the three
    # accents stay distinguishable even on monochrome wallpapers (verified:
    # without this, 10/10 test wallpapers collapse to same-hue accents).
    "secondary":                  "color6.rotate(120)",
    "on_secondary":               "color6.rotate(120).darken(0.45).desaturate(0.6)",
    "secondary_container":        "color6.rotate(120).darken(0.18)",
    "on_secondary_container":     "color6.rotate(120).lighten(0.4)",
    "secondary_fixed":            "color6.rotate(120).lighten(0.25)",
    "secondary_fixed_dim":        "color6.rotate(120).lighten(0.08)",
    "on_secondary_fixed":         "color6.rotate(120).darken(0.38)",
    "on_secondary_fixed_variant": "color6.rotate(120).darken(0.22)",
    "tertiary":                   "color5.rotate(240)",
    "on_tertiary":                "color5.rotate(240).darken(0.45).desaturate(0.5)",
    "tertiary_container":         "color5.rotate(240).darken(0.2)",
    "on_tertiary_container":      "color5.rotate(240).lighten(0.4)",
    "tertiary_fixed":             "color5.rotate(240).lighten(0.25)",
    "tertiary_fixed_dim":         "color5.rotate(240).lighten(0.08)",
    "on_tertiary_fixed":          "color5.rotate(240).darken(0.38)",
    "on_tertiary_fixed_variant":  "color5.rotate(240).darken(0.22)",
    # Error family is a hard-coded Material dark error triad. hellwal sorts its
    # palette by luminance, so no color0-15 slot is guaranteed a red hue (on some
    # wallpapers color1 is navy/blue/green). A static red keeps the semantic
    # "error = red" contract identical to matugen's Material output. Swap the
    # values to "colorN..." expressions to re-derive from the wallpaper instead.
    "error":                      "#ffb4ab",
    "on_error":                   "#690005",
    "error_container":            "#93000a",
    "on_error_container":         "#ffdad6",
    # Outline ops are deliberately gentle: darken() on a mid slot clamps to black
    # fast (measured: darken(0.5) -> 1.11:1 on dense wallpapers).
    "outline":                    "color15.desaturate(0.7).darken(0.15)",
    "outline_variant":            "color15.desaturate(0.6).darken(0.2)",
    "shadow":                     "color0.darken(1.0)",
    "scrim":                      "color0.darken(1.0)",
    "inverse_surface":            "color15.desaturate(0.15).lighten(0.05)",
    "inverse_on_surface":         "color0.lighten(0.2)",
    "inverse_primary":            "color13.lighten(0.35)",
    "source_color":               "color13",
}

# Templates to convert (same filenames that matugen's config.toml references,
# plus the small color files used by the GNOME settings engine).
FILES = [
    "btop.theme",
    "cava-colors.ini",
    "clock-rs-conf.toml",
    "clock-color.css",
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
    "search-light.css",
    "starship.toml",
    "yazi.toml",
    "zen-userchrome.css",
    "zen-usercontent.css",
]

PLACEHOLDER = re.compile(
    r"{{\s*colors\.(\w+)\.default\."
    r"(hex|hex_stripped|rgba|red|green|blue)"
    r"(\s*\|\s*auto_lightness\s*:\s*[\d.]+\s*)?\s*}}"
)


def _hex_channels(value):
    v = value.lstrip("#")
    if len(v) != 6:
        raise ValueError(f"bad literal hex in ROLES table: {value}")
    return int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16)


def expression(role, kind):
    base = ROLES.get(role)
    if base is None:
        raise KeyError(f"no mapping for role: {role}")

    # Literal CSS colors are emitted verbatim; channel forms are computed here.
    if base.startswith("#"):
        r, g, b = _hex_channels(base)
        if kind == "hex":
            return base
        if kind == "hex_stripped":
            return base.lstrip("#")
        if kind == "rgba":
            return f"rgba({r}, {g}, {b}, 1)"
        chan = {"red": r, "green": g, "blue": b}[kind]
        return str(chan)
    if kind == "hex":
        return f"#%%{base}.hex%%"
    if kind == "hex_stripped":
        return f"%%{base}.hex%%"
    if kind == "rgba":
        return f"rgba(%%{base}.rgb%%, 1)"
    chan = {"red": "r", "green": "g", "blue": "b"}[kind]
    return f"%%{base}.{chan}%%"


def convert(content):
    def repl(m):
        role = m.group(1)
        kind = m.group(2)
        if m.group(3):
            # auto_lightness requests a readable on-color for the given role;
            # approximate it with the matching on_<role> expression.
            on_role = role if role.startswith("on_") else "on_" + role
            on_base = ROLES.get(on_role) or ROLES.get(role)
            if on_base.startswith("#"):
                return on_base
            return f"#%%{on_base}.hex%%"
        return expression(role, kind)

    out, n = PLACEHOLDER.subn(repl, content)
    return out, n


def _role_rgb(role):
    base = ROLES[role]
    if base.startswith("#"):
        r, g, b = _hex_channels(base)
        return f"{r} {g} {b}"
    return f"%%{base}.r%% %%{base}.g%% %%{base}.b%%"


def main():
    os.makedirs(DST, exist_ok=True)
    stats = []
    skipped = []
    for name in FILES:
        src = os.path.join(SRC, name)
        if not os.path.isfile(src):
            skipped.append(name)
            continue
        with open(src, encoding="utf-8") as f:
            content = f.read()
        out, n = convert(content)
        with open(os.path.join(DST, name), "w", encoding="utf-8") as f:
            f.write(out)
        stats.append((name, n))
    for name, n in stats:
        print(f"  {name:<32} {n:>4} placeholders")
    for name in skipped:
        print(f"  {name:<32} SKIPPED (not found)")

    # hellwal-colors.css: same CSS-variable layout as matugen-colors.css so the
    # fish pipeline can source it with the same reader.
    roles_hex = "".join(
        f"    --{r}: {expression(r, 'hex')};\n\n" for r in ROLES
    )
    roles_rgb = "".join(
        f"    --{r}_rgb: {_role_rgb(r)};\n\n" for r in ROLES
    )
    css = ":root {\n\n" + roles_hex + "\n" + roles_rgb + "}\n"
    with open(os.path.join(DST, "hellwal-colors.css"), "w", encoding="utf-8") as f:
        f.write(css)
    print(f"  {'hellwal-colors.css':<32} generated ({len(ROLES)} roles)")


if __name__ == "__main__":
    main()