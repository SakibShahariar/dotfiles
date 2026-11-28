#!/usr/bin/env -S fish --no-config

# ======================
# ⚙️ CONFIG
# ======================
set -g DARKMODE_LOCK /tmp/.dark-mode-self-toggle.lock

function _cleanup_lock --on-event fish_exit
    rm -f $DARKMODE_LOCK
end

set wallpaper_dir "/mnt/Storage/Wallpapers"
set spinner "globe"

# Nerd Font icons (built with printf -- fish echo -e has no \u escapes)
set -g IC_CLOCK (printf '\uf252')   # stopwatch
set -g IC_IMAGE (printf '\uf03e')   # image
set -g IC_WARN  (printf '\uf071')   # warning triangle
set -g IC_BOLT  (printf '\uf0e7')   # bolt
set -g IC_FLAG  (printf '\uf11d')   # flag-checkered

# Truecolor (24-bit) ANSI prefix + reset for icon glyphs, pulled from the
# last matugen scheme's primary. Falls back to neutral gray if unavailable.
set -g IC_RESET "\033[0m"
set -g IC_ACC ""
set -l css_file ~/.config/matugen/matugen-colors.css
if test -f "$css_file"
    set -l m (string match -r -- '--primary_rgb:\s*([0-9]+)\s+([0-9]+)\s+([0-9]+)' (grep -m1 -- '--primary_rgb' "$css_file"))
    if test (count $m) -eq 4
        set -g IC_ACC "\033[38;2;$m[2];$m[3];$m[4]m"
    end
end
test -n "$IC_ACC"; or set -g IC_ACC "\033[38;2;120;120;128m"

# ======================
# ⏱️ BENCHMARK HELPER
# ======================
function time_block -a name
    # Execute passed command or function natively. Per-block timing was
    # removed: eight date processes per run cost more than the numbers were
    # worth. The overall TOTAL PIPELINE TIME line still reports duration.
    $argv[2..-1]
end

# ======================
# 🧰 NATIVE PIPELINE FUNCTIONS
# ======================
function load_wallpapers
    find $wallpaper_dir -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' \)
end

function run_apply_wallpaper -a img_path
    set -l filename (path basename "$img_path")
    cp "$img_path" ~/.config/background.jpg

    # URI-encode the path: raw "file://$path" breaks on spaces, quotes and
    # non-ASCII names (e.g. "Mad Max Fury Road.jpg"). Fish's url escape is
    # byte-identical to pathlib.as_uri() and avoids a ~0.11s python startup.
    set -l img_uri "file://"(string escape --style=url -- "$img_path")
    gsettings set org.gnome.desktop.background picture-uri "$img_uri"
    gsettings set org.gnome.desktop.background picture-uri-dark "$img_uri"
    
    echo -e "$IC_ACC$IC_IMAGE$IC_RESET Wallpaper set to: $filename"
end

# Fire a helper script in the background. Timing is intentionally omitted.
function run_bg_timed -a name script
    bash $script &>/dev/null &
end

function run_folder_icons
    set -l script_dir (path dirname (status --current-filename))
    set -g FOLDER_ICONS_PID ""
    set -l theme (gsettings get org.gnome.desktop.interface icon-theme | tr -d "'")
    switch $theme
        case Material-Grad
            bash $script_dir/grad_icon.sh &>/dev/null &
        case Material-Solo '*'
            bash $script_dir/folder_icon.sh &>/dev/null &
    end
    set -g FOLDER_ICONS_PID $last_pid
end

function run_cursor_icons
    set -l script_dir (path dirname (status --current-filename))
    run_bg_timed "Cursor Icons" $script_dir/cursor_matugen.sh
end

# Read all colors from matugen-colors.css once into $MC_<role> variables.
function load_matugen_colors
    set -l file ~/.config/matugen/matugen-colors.css
    test -f $file; or return 1

    while read -l line
        set -l m (string match -r -- '^\s*--([a-zA-Z0-9_]+):\s*([^;]+);' $line)
        test (count $m) -ge 3; or continue
        set -g "MC_$m[2]" (string trim $m[3])
    end < $file
end

# Build `r, g, b` from a MC_<name>_rgb like `17 19 24`.
function mc_rgb -a name
    set -l k "MC_$name"_rgb
    eval "set -l v \$$k"
    string split ' ' $v | string join ', '
end

# Build `rgba(r, g, b, alpha)` from a MC role.
function mc_rgba -a name alpha
    echo "rgba("(mc_rgb $name)", $alpha)"
end

function run_gnome_settings
    load_matugen_colors; or return

    # The writes are independent. Background them all and wait only on these
    # PIDs so we pay one dconf startup instead of eight serial forks.
    set -l pids

    # --- O-Tiling ---
    set -l color (mc_rgba primary 0.5)
    if test -n "$color"
        dconf write /org/gnome/shell/extensions/o-tiling/hint-color-rgba "'$color'" &
        set pids $pids $last_pid
    end

    # --- Clock (lockscreen) ---
    dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/time-font-color "'"(mc_rgba primary 1)"'" &
    set pids $pids $last_pid
    dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/date-font-color "'"(mc_rgba on_surface_variant 1)"'" &
    set pids $pids $last_pid
    dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/command-output-font-color "'"(mc_rgba secondary 1)"'" &
    set pids $pids $last_pid
    dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/hint-font-color "'"(mc_rgba surface_variant 1)"'" &
    set pids $pids $last_pid

    wait $pids

    # --- Accent chooser ---
    set -l primary "$MC_primary"
    if test -n "$primary"
        set -l clean_bg (string replace -a "'" "" "$primary")
        bash ~/Scripts/choose-accent.sh "$clean_bg" &>/dev/null &
    end
end

function run_sync_darkreader
    set -l DB "/home/sakib/.zen/xm5pwzyv.test/storage-sync-v2.sqlite"

    if test -f $DB
        load_matugen_colors; or return
        set -l BG "$MC_background"
        set -l FG "$MC_primary"

        if test -n "$BG"; and test -n "$FG"
            sqlite3 $DB "
            UPDATE storage_sync_data
            SET data = json_set(
                data,
                '\$.theme.darkSchemeBackgroundColor', '$BG',
                '\$.theme.darkSchemeTextColor', '$FG',
                '\$.theme.scrollbarColor', '$FG'
            )
            WHERE ext_id = 'addon@darkreader.org';
            " &>/dev/null
        end
    end
end

function run_sync_zen_boost
    set -l script_dir (path dirname (status --current-filename))

    if test -f "$script_dir/update-boost.js"
        node "$script_dir/update-boost.js" &>/dev/null
    else
        echo "⚠️ update-boost.js not found in script directory"
    end
end

# ======================
# 🎛️ MAIN MENU
# ======================
# An optional first argument is an already-selected wallpaper path. Callers
# such as Wallmat's "Apply wallpaper + Matugen" use it to run this full
# pipeline without opening the interactive picker.
set -g wallpaper ""
if test (count $argv) -gt 0
    set -l provided "$argv[1]"
    if not test -f "$provided"
        echo -e "$IC_ACC$IC_WARN$IC_RESET Not a readable wallpaper: $provided"
        exit 3
    end
    set wallpaper (realpath "$provided")
end

set -l IC_POINTER (printf '\uf0a4')   # hand-point-right
set -l IC_FOLDER (printf '\uf07c')    # folder-open
set -l IC_DICE (printf '\uf522')      # dice
if test -z "$wallpaper"
    set choice (gum choose --cursor "$IC_POINTER" --header "Pick your vibe" \
        "$IC_FOLDER Pick Wallpaper" "$IC_DICE Random Wallpaper")

set -g wallpaper_paths (load_wallpapers)

set -g wallpaper ""

switch $choice
    case "$IC_FOLDER Pick Wallpaper"
        set wallpaper (env \
            MESA_DEBUG_OVERRIDE=0 \
            MESA_LOG_LEVEL=0 \
            GSK_RENDERER=gl \
            VK_INSTANCE_LAYERS= \
            VK_LAYER_PATH= \
            python3 ~/Projects/wallmat/src/main.py "$wallpaper_dir" --plain 2>/dev/null | string trim -c "\r\n")
        # After a pipeline fish's $status is the LAST command's status
        # (string trim returns 1 on empty input). $pipestatus[1] is the
        # picker's real exit code.
        set -l picker_status $pipestatus[1]
        switch $picker_status
            case 2
                echo -e "$IC_ACC$IC_WARN$IC_RESET Wallpaper selection cancelled. Exiting."
                exit 2
            case 3
                echo -e "$IC_ACC$IC_WARN$IC_RESET Wallpaper folder is missing or unreadable: $wallpaper_dir"
                exit 3
            case 4
                echo -e "$IC_ACC$IC_WARN$IC_RESET No supported wallpapers found or scan failed."
                exit 4
            case '*'
                if test $picker_status -ne 0
                    echo -e "$IC_ACC$IC_WARN$IC_RESET Wallmat picker failed (exit $picker_status)."
                    exit $picker_status
                end
        end

    case "$IC_DICE Random Wallpaper"
        if test (count $wallpaper_paths) -gt 0
            set wallpaper (random choice $wallpaper_paths)
        end
    end
end

if test -z "$wallpaper"
    echo -e "$IC_ACC$IC_WARN$IC_RESET No wallpaper selected or folder is empty. Exiting."
    exit 1
end

# ======================
# 🚀 EXECUTION PIPELINE
# ======================
set pipeline_start (date +%s%3N)

touch $DARKMODE_LOCK

# Detect current system mode
set raw_scheme (gsettings get org.gnome.desktop.interface color-scheme)
if string match -q "*prefer-dark*" $raw_scheme
    set -g mode "dark"
else
    set -g mode "light"
end

# 1. Fire off wallpaper update in the background simultaneously with Matugen
run_apply_wallpaper "$wallpaper" &
set -l wallpaper_pid $last_pid

# 2. Run Matugen Theme Generation, guarded against no-op re-runs.
# A repeat run with the SAME wallpaper (path+mtime) and mode skips the ~2.4s
# template regeneration entirely. Delete ~/.cache/matugen/last_theme_run to
# force a full regeneration (or the token is invalidated on any real change).
set -l last_run_file "$HOME/.cache/matugen/last_theme_run"
set -l wp_mtime (stat -c %Y "$wallpaper" 2>/dev/null; or echo 0)
set -l token "$wallpaper|$wp_mtime|$mode"
if test -f "$last_run_file"
    and string match -q -- "$token" (string trim (cat "$last_run_file"))
    echo -e "$IC_ACC$IC_BOLT$IC_RESET Accent unchanged ($wallpaper) — skipping Matugen Theme Gen."
else
    time_block "Matugen Theme Gen" matugen image "$wallpaper" --type scheme-smart --mode $mode
    mkdir -p "$HOME/.cache/matugen"
    echo "$token" > "$last_run_file"
    # Templates just rewritten — reload apps in parallel (duration prints when done)
    run_bg_timed "App Reloads" ~/.config/matugen/post-hook-scripts/reload-apps.sh
end

# Ensure wallpaper application has fully completed before moving forward
wait $wallpaper_pid

# 3. Trigger all independent background sync/icon hooks concurrently
# (real duration is reported by each job itself, once it completes)
run_folder_icons
run_cursor_icons
run_sync_zen_boost &

# Run core GNOME settings
time_block "GNOME Settings Engine" run_gnome_settings

# 4. Final layout hook. The folder-icon recolor runs in parallel and is not
# waited on; verified over 10 wallpaper changes that the shell reload picks up
# the final icon colors.
time_block "Matugen Merge Layout Hook" bash "/home/sakib/.config/matugen/post-hook-scripts/merge-layout.sh"

echo "Applied theme for: $mode"

# No dark/light-mode write happens here (only a read above), so the listener
# never sees a self-triggered change and there is nothing to wait out.
rm -f $DARKMODE_LOCK

set pipeline_end (date +%s%3N)
set total_ms (math "$pipeline_end - $pipeline_start")
set total_sec (math -s2 "$total_ms / 1000")

echo -e "\n$IC_ACC$IC_FLAG$IC_RESET \033[1;36m[TOTAL PIPELINE TIME]\033[0m: \033[1;32m\"$total_sec\"s\033[0m (\"$total_ms\"ms)"
