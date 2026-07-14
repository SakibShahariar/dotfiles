#!/usr/bin/env python3
"""
metadata_generator.py — writes a standards-compliant index.theme for each
compiled Bibata-Matugen cursor theme.

WHY THIS MATTERS
-----------------
GNOME Tweaks/Settings, and any XCursor-consuming toolkit, only recognizes
a directory under ~/.icons (or $XDG_DATA_HOME/icons) as a cursor theme if
it contains BOTH:
  1. a `cursors/` subdirectory with compiled Xcursor binaries, AND
  2. an index.theme file with a valid [Icon Theme] section.

Get the index.theme wrong (missing Name key, wrong section header casing,
BOM in the file, CRLF line endings, etc.) and the theme either silently
fails to appear in the picker, or appears with a blank name — with zero
error message, which is exactly the kind of bug that generates a wall of
confused GNOME-Look.org comments.

WHAT THIS WRITES
----------------
[Icon Theme]
Name=<human-readable display name>
Comment=<description>
Inherits=<fallback theme>

`Name` here is purely cosmetic (shown in GNOME Tweaks' picker) — it is
NOT what gsettings/hyprctl use to select the theme. That's always the
folder name (e.g. "Bibata-Matugen-Ice-Blue"), which cursor_matugen.sh
already handles correctly and is untouched by this script.

`Inherits` matters functionally: if Bibata's own render ever misses a
cursor shape (some apps request obscure X11 cursor names), the toolkit
falls back to the inherited theme instead of showing a broken/missing
cursor. Defaults to "Adwaita" since it ships with GTK on virtually every
Linux desktop and is a safe universal fallback — override with
--inherits if you'd rather fall back to Bibata-Modern-Classic (only
safe if you can guarantee that's installed on the end user's system too,
which you generally can't for a GNOME-Look.org package).

USAGE
-----
Batch mode (regenerate for every installed theme — run this after a
full compile, or whenever packaging for GNOME-Look.org):

    python3 metadata_generator.py

Single-theme mode (called from compile_matugen_packs.fish right after
each theme compiles, so a bad index.theme is caught immediately instead
of surfacing 28 themes later):

    python3 metadata_generator.py --theme Ice-Blue

Options:
    --install-dir DIR   Where compiled themes live (default: $BIBATA_MATUGEN_INSTALL_DIR or ~/.icons)
    --themes-json PATH  Canonical theme table (default: themes.json next to this script)
    --inherits NAME     Fallback theme for missing cursor shapes (default: Adwaita)
    --dry-run           Print what would be written without touching disk
"""

import argparse
import json
import os
import sys
from pathlib import Path

DEFAULT_INHERITS = "Adwaita"
THEME_PREFIX = "Bibata-Matugen-"


def display_name(theme_key: str) -> str:
    """'Ice-Blue' -> 'Bibata Matugen Ice Blue' (cosmetic only)."""
    return "Bibata Matugen " + theme_key.replace("-", " ")


def build_index_theme_content(name: str, comment: str, inherits: str) -> str:
    # Written by hand (not via configparser) to guarantee exact formatting:
    # no quoting, no key reordering, LF line endings, no BOM — all things
    # that have broken real-world index.theme files in the wild.
    lines = [
        "[Icon Theme]",
        f"Name={name}",
        f"Comment={comment}",
    ]
    if inherits:
        lines.append(f"Inherits={inherits}")
    return "\n".join(lines) + "\n"


def validate_theme_dir(theme_dir: Path) -> list[str]:
    """Returns a list of problems found (empty list = looks fine)."""
    problems = []
    if not theme_dir.is_dir():
        problems.append(f"directory does not exist: {theme_dir}")
        return problems

    cursors_dir = theme_dir / "cursors"
    if not cursors_dir.is_dir():
        problems.append(f"missing 'cursors/' subdirectory (theme won't be recognized as an XCursor theme)")
    elif not any(cursors_dir.iterdir()):
        problems.append(f"'cursors/' subdirectory exists but is empty")

    return problems


def write_index_theme(theme_dir: Path, theme_key: str, comment: str,
                       inherits: str, dry_run: bool) -> bool:
    content = build_index_theme_content(display_name(theme_key), comment, inherits)
    target = theme_dir / "index.theme"

    if dry_run:
        print(f"--- would write {target} ---")
        print(content, end="")
        return True

    try:
        target.write_text(content, encoding="utf-8", newline="\n")
        return True
    except OSError as e:
        print(f"✗ Failed to write {target}: {e}", file=sys.stderr)
        return False


def main():
    script_dir = Path(__file__).resolve().parent
    default_install_dir = os.environ.get("BIBATA_MATUGEN_INSTALL_DIR", str(Path.home() / ".icons"))

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--install-dir", default=default_install_dir,
                         help="Where compiled themes live (default: %(default)s)")
    parser.add_argument("--themes-json", default=str(script_dir / "themes.json"),
                         help="Canonical theme table (default: %(default)s)")
    parser.add_argument("--inherits", default=DEFAULT_INHERITS,
                         help="Fallback theme for missing cursor shapes (default: %(default)s). Pass '' to omit.")
    parser.add_argument("--theme", default=None,
                         help="Only regenerate for this single theme key (e.g. 'Ice-Blue'), not the whole set")
    parser.add_argument("--dry-run", action="store_true",
                         help="Print what would be written without touching disk")
    args = parser.parse_args()

    themes_path = Path(args.themes_json)
    if not themes_path.is_file():
        print(f"Error: themes.json not found at {themes_path}", file=sys.stderr)
        sys.exit(1)

    with open(themes_path, "r", encoding="utf-8") as f:
        themes = json.load(f)

    if args.theme:
        if args.theme not in themes:
            print(f"Error: '{args.theme}' not found in {themes_path}", file=sys.stderr)
            sys.exit(1)
        theme_keys = [args.theme]
    else:
        theme_keys = list(themes.keys())

    install_dir = Path(args.install_dir)
    ok_count = 0
    fail_count = 0
    skip_count = 0

    for key in theme_keys:
        folder_name = f"{THEME_PREFIX}{key}"
        theme_dir = install_dir / folder_name

        problems = validate_theme_dir(theme_dir)
        if problems:
            skip_count += 1
            print(f"⚠ Skipping '{folder_name}':", file=sys.stderr)
            for p in problems:
                print(f"    - {p}", file=sys.stderr)
            continue

        comment = f"Wallpaper-matched M3 cursor theme, tonal variant: {key.replace('-', ' ')}"
        if write_index_theme(theme_dir, key, comment, args.inherits, args.dry_run):
            ok_count += 1
            if not args.dry_run:
                print(f"✓ Wrote index.theme for {folder_name}")
        else:
            fail_count += 1

    print("")
    print(f"metadata_generator finished: {ok_count} written, {skip_count} skipped (not compiled), {fail_count} failed")

    if fail_count > 0:
        sys.exit(1)
    if ok_count == 0:
        print("Nothing was written — did you run compile_matugen_packs.fish first?", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()