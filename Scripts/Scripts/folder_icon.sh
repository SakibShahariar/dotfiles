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

mono_theme="${XDG_DATA_HOME:-$HOME/.local/share}/icons/Material-Solo"

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
# Normalise to lowercase: the guards below are case-sensitive [[ ]] tests while
# these values are read verbatim out of the SVGs, so a file holding #C8C8AE
# would otherwise slip past a "!=" that is meant to catch it.
color_src=$(rg -l -F "ColorScheme-Highlight" "$mono_theme/apps" -g '*.svg' 2>/dev/null | head -1)
if [[ -n "$color_src" ]]; then
    actual_hex=$(grep -ozP 'ColorScheme-Highlight\s*\{\s*color:\s*\K#[0-9a-fA-F]+' "$color_src" | tr '\0' '\n' | head -1)
    actual_hex=${actual_hex,,}
fi
bg_src=$(rg -l -F "ColorScheme-Background" "$mono_theme/apps" -g '*.svg' 2>/dev/null | head -1)
if [[ -n "$bg_src" ]]; then
    actual_on=$(grep -ozP 'ColorScheme-Background\s*\{\s*color:\s*\K#[0-9a-fA-F]+' "$bg_src" | tr '\0' '\n' | head -1)
    actual_on=${actual_on,,}
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
        p_old_hex=${p_old_hex,,}
        # Folder emblem (ColorScheme-Background), where present.
        pe_bg=$(find "$places_dir/scalable" "$places_dir/symbolic" -path '*/places/*.svg' -print -quit 2>/dev/null)
        if [[ -n "$pe_bg" ]]; then
            p_old_on=$(grep -ozP 'ColorScheme-Background\s*\{\s*color:\s*\K#[0-9a-fA-F]+' "$pe_bg" | tr '\0' '\n' | head -1)
            p_old_on=${p_old_on,,}
        fi
        # If places diverged from apps' accent, fix places on its own first.
        if [[ -n "$p_old_hex" && "$p_old_hex" != "$old_hex" && "$p_old_hex" != "$target_hex" ]]; then
            rg -0 -l -F "$p_old_hex" "$places_dir" -g '*.svg' 2>/dev/null \
                | xargs -r -0 -P 6 sed -i "s/$p_old_hex/$target_hex/gI"
        fi
        # Folder emblem self-heal. Same three guards as the apps/ sweep below,
        # for the same reasons: p_old_on is sampled from places/ on disk, and
        # a sweep driven by a sample will happily repaint a colour that the
        # sample never meant to represent. Block-scoped for the same reason -
        # the line-based form could not see a multi-line Background block and
        # so matched only unrelated single-line `color:` declarations.
        if [[ "$p_old_on" == "#"?????? && "$p_old_on" != "$on_primary_hex" \
              && "$p_old_on" != "$target_hex" && "$p_old_on" != "$old_hex" \
              && "$p_old_on" != "$p_old_hex" ]]; then
            rg -0 -l -F "ColorScheme-Background" "$places_dir" -g '*.svg' 2>/dev/null \
                | xargs -r -0 -P 6 perl -0777 -i -pe \
                    "s{(ColorScheme-Background\\s*\\{\\s*color:\\s*)\\Q$p_old_on\\E}{\${1}$on_primary_hex}gi"
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
    #
    # In apps/ this step needs three guards it never had, and it is the only
    # genuinely destructive step in the script:
    #   1. Every ColorScheme class in apps/ resolves to the ACCENT (primary) -
    #      Text, Background, Accent and ButtonText are all the same value, and
    #      on_primary is not used there at all. So a colour read back out of
    #      ColorScheme-Background IS the accent, and sweeping it into
    #      on_primary would repaint the accent of every app file in one tone
    #      (measured: 1028 files hold a single-line `color:`, 3237 occurrences).
    #      Only the fast-path exit above was stopping that from firing.
    #   2. Well-formed hex, mirroring the accent guard at line 108. A truncated
    #      or empty value would otherwise sed a bare prefix and corrupt files.
    #   3. Rewrite only inside a ColorScheme-Background block, whole-file, so
    #      the multi-line declarations that every apps/ file actually uses are
    #      handled and no unrelated `color:` (a style=, a fill, a decoy) can
    #      match. The old line-based `s/color:$old_on/.../gI` could not reach a
    #      multi-line block at all, so it matched only the unrelated ones.
    if [[ -n "$actual_on" && "$actual_on" != "$on_primary_hex" ]]; then
        old_on="$actual_on"
    fi
    if [[ "$old_on" == "#"?????? && "$old_on" != "$on_primary_hex" \
          && "$old_on" != "$target_hex" && "$old_on" != "$old_hex" ]]; then
        # Both values are validated `#`+6-hex above, so splicing them straight
        # into the program text is injection-safe. Do NOT pass them via ENV:
        # an unset key interpolates as empty, which degrades the pattern to
        # "(ColorScheme-Background...color:)" and the replacement to "${1}",
        # so it rewrites each match with itself - a silent no-op that still
        # writes the new state and looks like a successful repair.
        rg -0 -l -F "ColorScheme-Background" "$mono_theme/apps" -g '*.svg' 2>/dev/null \
            | xargs -r -0 -P 6 perl -0777 -i -pe \
                "s{(ColorScheme-Background\\s*\\{\\s*color:\\s*)\\Q$old_on\\E}{\${1}$on_primary_hex}gi"
        # Never fail quietly: if the old colour survives inside a Background
        # block the substitution did not take, and the next run reads it back
        # as authoritative and keeps "repairing" towards it.
        _stale=$(rg -0 -l -F "ColorScheme-Background" "$mono_theme/apps" -g '*.svg' 2>/dev/null \
            | xargs -r -0 -P 6 perl -0777 -ne \
                'print "$ARGV\n" if /(ColorScheme-Background\s*\{\s*color:\s*)\Q'"$old_on"'\E/i' \
            | head -1)
        [[ -n "$_stale" ]] && \
            printf 'folder_icon.sh: emblem %s survived the apps/ sweep (%s)\n' "$old_on" "$_stale" >&2
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