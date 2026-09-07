#!/usr/bin/env bash
set -uo pipefail

# Detection greps can legitimately return no match (empty rc). They must not
# abort the whole script, so `set -e` is NOT used; every command checks its
# own preconditions instead.

# 1. Grab Matugen accent + on_primary colors.
# Read with bash builtins only (no exec spawn) so the fast path is millisecond-fast.
colors_file=~/.config/matugen/matugen-colors.css
state=~/.local/share/matugen-icon-themes/state
colors_css=$(<"$colors_file")
if [[ $colors_css =~ (--primary:[[:space:]]*#([0-9a-fA-F]{6})) ]]; then
    target_hex=#${BASH_REMATCH[2]}
fi
if [[ $colors_css =~ (--on_primary:[[:space:]]*#([0-9a-fA-F]{6})) ]]; then
    on_primary_hex=#${BASH_REMATCH[2]}
fi
[[ -n "$target_hex" && -n "$on_primary_hex" ]] || exit 1

theme_dir=~/.icons/Tela-Hybrid
mono_theme=~/.icons/Material-Tela

# Read previous accent state (used only as a fallback).
# The session authority is always the FILES: the hybrid path derives its
# baseline from the SVGs (recolor_theme), and we mirror that below for the
# mono theme. This makes the whole recalc self-healing - a partial/failed
# swap can never be locked in by trusting a state file that no longer matches
# what is actually on disk.
old_hex=""
old_on=""
if [[ -f $state ]]; then
    { read -r old_hex; read -r old_on; } < "$state"
fi

# Derive the accent (and emblem) colors the mono theme ACTUALLY contains now,
# from the first SVG that declares the ColorScheme classes.
actual_hex=""
actual_on=""
color_src=$(rg -l -F "ColorScheme-Highlight" "$mono_theme" -g '*.svg' 2>/dev/null | head -1)
if [[ -n "$color_src" ]]; then
    actual_hex=$(grep -ozP 'ColorScheme-Highlight\s*\{\s*color:\s*\K#[0-9a-fA-F]+' "$color_src" | tr '\0' '\n' | head -1)
fi
bg_src=$(rg -l -F "ColorScheme-Background" "$mono_theme" -g '*.svg' 2>/dev/null | head -1)
if [[ -n "$bg_src" ]]; then
    actual_on=$(grep -ozP 'ColorScheme-Background\s*\{\s*color:\s*\K#[0-9a-fA-F]+' "$bg_src" | tr '\0' '\n' | head -1)
fi

# Fast path: accent unchanged on disk AND emblem matches -> return in ms.
# We verify the FILES, not the state file: if a prior change was partial,
# state would claim "target" while the SVGs still hold a stale accent. The old
# check (state == target) then locked the corruption in for every later run.
if [[ -n "$actual_hex" && "$actual_hex" == "$target_hex" && "$old_on" == "$on_primary_hex" ]]; then
    exit 0
fi

# Repair: if the theme diverged from state, swap from the color that is really
# in the files (e.g. stale #a0d49b) to the target, not from the state-tracked one.
if [[ -n "$actual_hex" && "$actual_hex" != "$target_hex" ]]; then
    old_hex="$actual_hex"
fi

# Pre-toggle to Adwaita BEFORE touching any SVG: this drops every GTK app's
# cached renders of the old color and parks them on a neutral theme, so no
# app can ever render a half-recolored Material-Tela mid-swap. We are already
# past the fast-path early exit, so this only runs on a real accent change.
active=$(gsettings get org.gnome.desktop.interface icon-theme | tr -d "'")
gsettings set org.gnome.desktop.interface icon-theme Adwaita

# 2. Fast Targeted Recolor
recolor_theme() {
    local dir=$1 hex=$2 on_primary=$3
    [[ -d $dir ]] || return 0

    local sample
    sample=$(find "$dir" -path '*/places/*.svg' -print -quit)
    [[ -n "$sample" ]] || return 0

    local old_hex old_bg_hex bg_sample
    old_hex=$(grep -ozP 'ColorScheme-Highlight\s*\{\s*color:\s*\K#[0-9a-fA-F]+' "$sample" | tr '\0' '\n' | head -1)
    [[ -n "$old_hex" ]] || return 0

    # Emblem/logo color (ColorScheme-Background). Only scalable has it.
    # Tela layout keeps scalable at '<dir>/scalable/places'; YAMIS layout
    # mirrors it as '<dir>/places/scalable'. Check both.
    bg_sample=$(find "$dir/scalable/places" "$dir/places/scalable" -path '*/places/*.svg' -print -quit 2>/dev/null)
    old_bg_hex=""
    if [[ -n "$bg_sample" ]]; then
        old_bg_hex=$(grep -ozP 'ColorScheme-Background\s*\{\s*color:\s*\K#[0-9a-fA-F]+' "$bg_sample" | tr '\0' '\n' | head -1)
    fi

    (
        cd "$dir" || exit
        find . -type f -path '*/places/*.svg' -print0 | xargs -0 -P "$(nproc)" sed -i "s/$old_hex/$hex/gI"
        if [[ -n "$old_bg_hex" ]]; then
            # Only CSS class defs use `color:` - the hardcoded fill stays untouched.
            find . -type f -path '*/places/*.svg' -print0 | xargs -0 -P "$(nproc)" sed -i "s/color:$old_bg_hex/color:$on_primary/gI"
        fi
    )

    gtk-update-icon-cache -f -t "$dir" 2>/dev/null
    gtk4-update-icon-cache -f -t "$dir" 2>/dev/null
}

# 3a. Recolor Tela folders (in place; idempotent via the ColorScheme class hook)
recolor_theme "$theme_dir" "$target_hex" "$on_primary_hex"

# 3b. Recolor the monochrome app theme (Material-Tela) to the accent.
# YAMIS icons are single-fill, so the whole set is one hex swap. Track the
# previous accent in a state file and swap in place - no full re-copy, no
# cache rebuild (the file *index* never changes, only fill colors).
if [[ -z "$old_hex" ]]; then
    # First run after migration: theme may already be at any accent.
    # Just record the current one so the next change has a baseline to swap from.
    printf '%s\n%s\n' "$target_hex" "$on_primary_hex" > "$state"
elif [[ -d $mono_theme ]]; then
    # Sanity: only act if the old accent is `#`-prefixed (a bare hex means
    # corruption and would otherwise silently no-op the swap).
    if [[ "$old_hex" == "#"?????? ]]; then
        # Mono SVGs: swap fill. Only touch files that actually contain old accent.
        rg -0 -l -F "$old_hex" "$mono_theme" -g '*.svg' -g '!places/**' 2>/dev/null \
            | xargs -r -0 -P "$(nproc)" sed -i "s/$old_hex/$target_hex/gI"
        # Folder SVG `color:` CSS class + any `color:` usages of the old accent.
        rg -0 -l -F "color:$old_hex" "$mono_theme" -g '*.svg' 2>/dev/null \
            | xargs -r -0 -P "$(nproc)" sed -i "s/color:$old_hex/color:$target_hex/gI"
    fi
    # Folder emblem (on_primary). Self-heal like the accent: if the emblem on
    # disk diverged from the state-tracked one, repair from the actual file color.
    if [[ -n "$actual_on" && "$actual_on" != "$on_primary_hex" ]]; then
        old_on="$actual_on"
    fi
    if [[ -n "$old_on" && "$old_on" != "$on_primary_hex" ]]; then
        rg -0 -l -F "color:$old_on" "$mono_theme" -g '*.svg' 2>/dev/null \
            | xargs -r -0 -P "$(nproc)" sed -i "s/color:$old_on/color:$on_primary_hex/gI"
    fi
    printf '%s\n%s\n' "$target_hex" "$on_primary_hex" > "$state"
fi

# The mono theme's cache ("icon-theme.cache") is only rebuilt by recolor_theme
# for the hybrid dir. The shell dash/grid icons read the MONO theme through
# GTK's GIconTheme, which trusts the cache file's mtime when deciding whether
# to re-read the tree. If we swap the SVG fill colors but leave this cache
# stale, the shell can keep rendering the old accent texture for the rest of
# the session (first run works, every later run shows the old color). Force a
# rebuild so the cache is always newer than the files it describes.
gtk-update-icon-cache -f -t "$mono_theme" 2>/dev/null

# 4. Instant UI Refresh (restore the active theme now that all files are final).
# Then SLEEP. GNOME Shell flushes its icon texture cache on the icon-theme
# change signal; if the next step (merge-layout -> user-theme reload) lands in
# the same instant, the shell can repaint from the still-cached OLD texture
# before the flush is processed. A settle lets the flush fully land, so the
# subsequent shell reload repaints from the final files only.
gsettings set org.gnome.desktop.interface icon-theme "$active"
sleep 0.6

# 5. Nautilus keeps per-window icon caches that survive the icon-theme toggle;
# restart it after the swap so open file-manager windows re-read the recolored
# files (it auto-reopens on next use).
pkill -x nautilus 2>/dev/null || true