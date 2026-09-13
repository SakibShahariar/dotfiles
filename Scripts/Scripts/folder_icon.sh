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

mono_theme=~/.icons/Material-Tela

# Read previous accent state (used only as a fallback).
# The session authority is always the FILES: we derive the theme's current
# accent from the SVGs directly, so this recalc is self-healing - a
# partial/failed swap can never be locked in by trusting a state file that no
# longer matches what is actually on disk.
old_hex=""
old_on=""
if [[ -f $state ]]; then
    { read -r old_hex; read -r old_on; } < "$state"
fi

# Derive the accent (and emblem) colors the app icons ACTUALLY contain now,
# from the first app SVG that declares the ColorScheme classes.
actual_hex=""
actual_on=""
color_src=$(rg -l -F "ColorScheme-Highlight" "$mono_theme/apps" -g '*.svg' 2>/dev/null | head -1)
if [[ -n "$color_src" ]]; then
    actual_hex=$(grep -ozP 'ColorScheme-Highlight\s*\{\s*color:\s*\K#[0-9a-fA-F]+' "$color_src" | tr '\0' '\n' | head -1)
fi
bg_src=$(rg -l -F "ColorScheme-Background" "$mono_theme/apps" -g '*.svg' 2>/dev/null | head -1)
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

# 2. Material-Tela folder icons (places/) + app icons (apps/) both carry the
# accent as raw hex in their ColorScheme classes. Normally they stay in
# lockstep, so a single combined sweep below recolors both trees under one
# parallel pool; if they ever diverge (partial failure), each tree self-heals.
places_dir="$mono_theme/places"
p_old_hex=""
p_old_on=""
if [[ -d $places_dir ]]; then
    psample=$(find "$places_dir" -path '*/places/*.svg' -print -quit)
    if [[ -n "$psample" ]]; then
        p_old_hex=$(grep -ozP 'ColorScheme-Highlight\s*\{\s*color:\s*\K#[0-9a-fA-F]+' "$psample" | tr '\0' '\n' | head -1)
        # Folder emblem (ColorScheme-Background), where present.
        pe_bg=$(find "$places_dir/scalable" "$places_dir/symbolic" -path '*/places/*.svg' -print -quit 2>/dev/null)
        if [[ -n "$pe_bg" ]]; then
            p_old_on=$(grep -ozP 'ColorScheme-Background\s*\{\s*color:\s*\K#[0-9a-fA-F]+' "$pe_bg" | tr '\0' '\n' | head -1)
        fi
        # If places diverged from apps' accent, fix places on its own first.
        if [[ -n "$p_old_hex" && "$p_old_hex" != "$old_hex" && "$p_old_hex" != "$target_hex" ]]; then
            rg -0 -l -F "$p_old_hex" "$places_dir" -g '*.svg' 2>/dev/null \
                | xargs -r -0 -P 6 sed -i "s/$p_old_hex/$target_hex/gI"
        fi
        # Folder emblem self-heal.
        if [[ -n "$p_old_on" && "$p_old_on" != "$on_primary_hex" ]]; then
            rg -0 -l -F "color:$p_old_on" "$places_dir" -g '*.svg' 2>/dev/null \
                | xargs -r -0 -P "$(nproc)" sed -i "s/color:$p_old_on/color:$on_primary_hex/gI"
        fi
    fi
fi

# 3. Accent sweep — app icons (apps/). One combined parallel pass recolors
# apps + places together (single xargs pool; the places divergent case was
# already fixed above, so any remaining old_hex in places is safe to swap
# too). Other categories (mimetypes, actions, status, etc.) stay untouched.
if [[ -z "$old_hex" ]]; then
    # First run after migration: theme may already be at any accent.
    # Just record the current one so the next change has a baseline to swap from.
    printf '%s\n%s\n' "$target_hex" "$on_primary_hex" > "$state"
elif [[ -d $mono_theme/apps ]]; then
    # Sanity: only act if the old accent is `#`-prefixed (a bare hex means
    # corruption and would otherwise silently no-op the swap).
    if [[ "$old_hex" == "#"?????? ]]; then
        # P6 saturates this 4-core NVMe better than nproc (4) for small SVG
        # writes; P8 is equivalent. Measured P4=0.65s vs P6/P8=0.40s.
        rg -0 -l -F "$old_hex" "$mono_theme/apps" "$places_dir" -g '*.svg' 2>/dev/null \
            | xargs -r -0 -P 6 sed -i "s/$old_hex/$target_hex/gI"
    fi
    # App emblem (on_primary). Self-heal like the accent: if the emblem on
    # disk diverged from the state-tracked one, repair from the actual file color.
    if [[ -n "$actual_on" && "$actual_on" != "$on_primary_hex" ]]; then
        old_on="$actual_on"
    fi
    if [[ -n "$old_on" && "$old_on" != "$on_primary_hex" ]]; then
        rg -0 -l -F "color:$old_on" "$mono_theme/apps" -g '*.svg' 2>/dev/null \
            | xargs -r -0 -P "$(nproc)" sed -i "s/color:$old_on/color:$on_primary_hex/gI"
    fi
    printf '%s\n%s\n' "$target_hex" "$on_primary_hex" > "$state"
fi

# The mono theme's cache ("icon-theme.cache") is what the shell dash/grid
# icons are read through, and GTK's GIconTheme trusts the cache file's mtime
# when deciding whether to re-read the tree. If we swap the SVG fill colors
# but leave this cache stale, the shell can keep rendering the old accent
# texture for the rest of the session (first run works, every later run shows
# the old color). Force a rebuild so the cache is always newer than the files
# it describes.
gtk-update-icon-cache -f -t "$mono_theme" 2>/dev/null

# 4. Instant UI Refresh (restore the active theme now that all files are final).
# Then SLEEP. GNOME Shell flushes its icon texture cache on the icon-theme
# change signal; if the next step (merge-layout -> user-theme reload) lands in
# the same instant, the shell can repaint from the still-cached OLD texture
# before the flush is processed. A settle lets the flush fully land, so the
# subsequent shell reload repaints from the final files only.
gsettings set org.gnome.desktop.interface icon-theme "$active"
sleep 0.15