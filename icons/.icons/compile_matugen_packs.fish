#!/usr/bin/env fish
# ~/.icons/compile_matugen_packs.fish - M3 Primary-Outline Compiler
#
# Reads the canonical theme table from themes.json (shared with
# cursor_matugen.sh / color_match.py) instead of an embedded array.
# This is the ONLY place theme colors should be edited — both the
# compiler and the runtime matcher read from the same file, so they
# can never silently drift apart again.

# SCRIPT_DIR: where this script + themes.json + color_match.py live.
# Can be anywhere (e.g. ~/Scripts, a cloned repo, etc).
set -l script_dir (dirname (readlink -f (status filename)))
set -l build_dir "$script_dir/bibata_cursor"
set -l themes_json "$script_dir/themes.json"

# INSTALL_DIR: where compiled cursor themes actually get installed.
# This MUST be a directory GNOME/X11/Hyprland search for cursor themes
# (~/.icons is the standard XDG location) — it is independent of
# wherever you keep the build scripts themselves. Override with:
#   set -x BIBATA_MATUGEN_INSTALL_DIR /custom/path
set -l install_dir $BIBATA_MATUGEN_INSTALL_DIR
if test -z "$install_dir"
    set install_dir "$HOME/.icons"
end
mkdir -p $install_dir

# --- Preflight checks -------------------------------------------------
if not command -v jq >/dev/null
    echo "Error: jq is required (used to read themes.json). Install it and retry." >&2
    exit 1
end

if not test -f $themes_json
    echo "Error: themes.json not found at $themes_json" >&2
    exit 1
end

if not test -d $build_dir
    echo "Cloning bibata_cursor source..."
    if not git clone https://github.com/rtgiskard/bibata_cursor $build_dir
        echo "Error: failed to clone bibata_cursor" >&2
        exit 1
    end
end

# --- Enumerate theme names from JSON (preserves file order) -----------
set -l theme_names (jq -r 'keys[]' $themes_json)

if test (count $theme_names) -eq 0
    echo "Error: themes.json contains no themes" >&2
    exit 1
end

set -l fail_count 0
set -l ok_count 0

for NAME in $theme_names
    set -l BODY (jq -r --arg n "$NAME" '.[$n].body' $themes_json)
    set -l PRIMARY (jq -r --arg n "$NAME" '.[$n].primary' $themes_json)
    set -l WATCH (jq -r --arg n "$NAME" '.[$n].watch' $themes_json)

    if test -z "$BODY" -o -z "$PRIMARY" -o -z "$WATCH" -o "$BODY" = "null"
        echo "⚠ Skipping '$NAME': missing body/primary/watch in themes.json" >&2
        set fail_count (math $fail_count + 1)
        continue
    end

    set -l theme_name "Bibata-Matugen-$NAME"
    echo "Processing M3 theme: $theme_name ($BODY / $PRIMARY / $WATCH)"

    set -l temp_run_dir "$build_dir/run_$NAME"
    rm -rf $temp_run_dir
    mkdir -p $temp_run_dir
    cp -r $build_dir/src $temp_run_dir/
    cp -r $build_dir/svg $temp_run_dir/
    cp -r $build_dir/config $temp_run_dir/

    cd $temp_run_dir

    # Note: colors[0] = body/container, colors[1] = outline/primary, colors[2] = watch-bg
    set -l py_status (python3 -c "
import json, sys
try:
    with open('config/render.json') as f:
        d = json.load(f)
    t = 'Bibata-Modern-Classic'
    d[t]['colors'][0]['replace'] = '$BODY'
    d[t]['colors'][1]['replace'] = '$PRIMARY'
    d[t]['colors'][2]['replace'] = '$WATCH'
    with open('config/render.json', 'w') as f:
        json.dump(d, f, indent=2)
except Exception as e:
    print(f'render.json patch failed: {e}', file=sys.stderr)
    sys.exit(1)
"; echo $status)

    if test "$py_status" != "0"
        echo "✗ Failed to patch render.json for $NAME, skipping" >&2
        cd $build_dir
        rm -rf $temp_run_dir
        set fail_count (math $fail_count + 1)
        continue
    end

    if not ./src/cursor_utils.py --x11 --hypr --theme "Bibata-Modern-Classic" --out-dir "out" >/dev/null 2>compile_err.log
        echo "✗ cursor_utils.py failed for $NAME:" >&2
        cat compile_err.log >&2
        cd $build_dir
        rm -rf $temp_run_dir
        set fail_count (math $fail_count + 1)
        continue
    end

    if test -d "out/Bibata-Modern-Classic"
        rm -rf "$install_dir/$theme_name"
        mv "out/Bibata-Modern-Classic" "$install_dir/$theme_name"
        set ok_count (math $ok_count + 1)
    else
        echo "✗ Expected output dir missing for $NAME" >&2
        set fail_count (math $fail_count + 1)
    end

    cd $build_dir
    rm -rf $temp_run_dir
end

echo ""
echo "M3 compilation finished: $ok_count succeeded, $fail_count failed."
echo "Installed to: $install_dir"

if test $fail_count -gt 0
    exit 1
end