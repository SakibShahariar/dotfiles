#!/usr/bin/env fish

# ======================
# ⚙️ CONFIG
# ======================
set -g DARKMODE_LOCK /tmp/.dark-mode-self-toggle.lock

function _cleanup_lock --on-event fish_exit
    rm -f $DARKMODE_LOCK
end

set wallpaper_dir "/mnt/Storage/Wallpapers"
set spinner "globe"

# Nerd Font icons
set -g IC_CLOCK (printf '\uf252')   # stopwatch
set -g IC_IMAGE (printf '\uf03e')   # image
set -g IC_WARN  (printf '\uf071')   # warning triangle
set -g IC_BOLT  (printf '\uf0e7')   # bolt
set -g IC_FLAG  (printf '\uf11d')   # flag-checkered

# Truecolor accent for icons, pulled from the last hellwal scheme's primary.
set -g IC_RESET "\033[0m"
set -g IC_ACC ""
set -l css_file ~/.config/hellwal/hellwal-colors.css
if test -f "$css_file"
    set -l m (string match -r -- '--primary_rgb:\s*([0-9]+)\s+([0-9]+)\s+([0-9]+)' (grep -m1 -- '--primary_rgb' "$css_file"))
    if test (count $m) -eq 4
        set -g IC_ACC "\033[38;2;$m[2];$m[3];$m[4]m"
    end
end
test -n "$IC_ACC"; or set -g IC_ACC "\033[38;2;120;120;128m"

# hellwal binary: prefer a system install, fall back to the local build.
set -g HELLWAL_CMD (command -v hellwal); or set -g HELLWAL_CMD "$HOME/hellwal/hellwal"

# ======================
# ⏱️ BENCHMARK HELPER
# ======================
function time_block -a name
    set -l start_ms (date +%s%3N)
    $argv[2..-1]
    set -l end_ms (date +%s%3N)
    set -l elapsed_ms (math "$end_ms - $start_ms")
    set -l elapsed_sec (math -s2 "$elapsed_ms / 1000")
    echo -e "$IC_ACC$IC_CLOCK$IC_RESET  \033[1;33m[$name]\033[0m took \033[1;32m\"$elapsed_sec\"s\033[0m (\"$elapsed_ms\"ms)"
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

    gsettings set org.gnome.desktop.background picture-uri "file://$img_path"
    gsettings set org.gnome.desktop.background picture-uri-dark "file://$img_path"

    echo -e "$IC_ACC$IC_IMAGE$IC_RESET Wallpaper set to: $filename"
end

function run_bg_timed -a name script
    set -l start_ms (date +%s%3N)
    bash $script &>/dev/null &
    set -l pid $last_pid
    begin
        wait $pid 2>/dev/null
        set -l end_ms (date +%s%3N)
        set -l elapsed_ms (math "$end_ms - $start_ms")
        set -l elapsed_sec (math -s2 "$elapsed_ms / 1000")
        echo -e "$IC_ACC$IC_CLOCK$IC_RESET  \033[1;33m[$name]\033[0m took \033[1;32m\"$elapsed_sec\"s\033[0m (\"$elapsed_ms\"ms)"
    end &
end

function run_folder_icons
    set -l script_dir (path dirname (status --current-filename))
    set -g FOLDER_ICONS_PID ""
    set -l start_ms (date +%s%3N)
    set -l theme (gsettings get org.gnome.desktop.interface icon-theme | tr -d "'")
    switch $theme
        case Material-Grad
            bash $script_dir/grad_icon.sh &>/dev/null &
        case Material-Solo '*'
            bash $script_dir/folder_icon.sh &>/dev/null &
    end
    set -g FOLDER_ICONS_PID $last_pid

    begin
        wait $FOLDER_ICONS_PID 2>/dev/null
        set -l end_ms (date +%s%3N)
        set -l elapsed_ms (math "$end_ms - $start_ms")
        set -l elapsed_sec (math -s2 "$elapsed_ms / 1000")
        echo -e "$IC_ACC$IC_CLOCK$IC_RESET  \033[1;33m[Folder Icons]\033[0m took \033[1;32m\"$elapsed_sec\"s\033[0m (\"$elapsed_ms\"ms)"
    end &
end

function run_cursor_icons
    set -l script_dir (path dirname (status --current-filename))
    run_bg_timed "Cursor Icons" $script_dir/cursor_matugen.sh
end

# Read all colors from hellwal-colors.css once into $HC_<role> variables.
function load_hellwal_colors
    set -l file ~/.config/hellwal/hellwal-colors.css
    test -f $file; or return 1

    while read -l line
        set -l m (string match -r -- '^\s*--([a-zA-Z0-9_]+):\s*([^;]+);' $line)
        test (count $m) -ge 3; or continue
        set -g "HC_$m[2]" (string trim $m[3])
    end < $file
end

# Build `r, g, b` from a HC_<name>_rgb like `17 19 24`.
function hc_rgb -a name
    set -l k "HC_$name"_rgb
    eval "set -l v \$$k"
    string split ' ' $v | string join ', '
end

function hc_rgba -a name alpha
    echo "rgba("(hc_rgb $name)", $alpha)"
end

function run_hellwal_gnome_settings
    load_hellwal_colors; or return

    # --- O-Tiling ---
    set -l color (hc_rgba primary 0.5)
    test -n "$color"; and dconf write /org/gnome/shell/extensions/o-tiling/hint-color-rgba "'$color'"

    # --- Clock (lockscreen) ---
    dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/time-font-color "'"(hc_rgba primary 1)"'"
    dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/date-font-color "'"(hc_rgba on_surface_variant 1)"'"
    dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/command-output-font-color "'"(hc_rgba secondary 1)"'"
    dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/hint-font-color "'"(hc_rgba surface_variant 1)"'"

    # --- Dynamic Music Pill ---
    dconf write /org/gnome/shell/extensions/dynamic-music-pill/sync-accent-color "true"
    set -l fg_rgb (hc_rgb primary)
    set -l bg_rgb (hc_rgb surface)
    dconf write /org/gnome/shell/extensions/dynamic-music-pill/custom-text-color "'$fg_rgb'"
    dconf write /org/gnome/shell/extensions/dynamic-music-pill/custom-bg-color "'$bg_rgb'"

    # --- Accent chooser ---
    set -l primary "$HC_primary"
    if test -n "$primary"
        set -l clean_bg (string replace -a "'" "" "$primary")
        bash ~/Scripts/choose-accent.sh "$clean_bg" &>/dev/null &
    end
end

function run_sync_darkreader
    set -l DB "/home/sakib/.zen/ke09ovgb.myuser/storage-sync-v2.sqlite"

    if test -f $DB
        load_hellwal_colors; or return
        set -l BG "$HC_background"
        set -l FG "$HC_primary"

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
set -l IC_POINTER (printf '\uf0a4')   # hand-point-right
set -l IC_FOLDER (printf '\uf07c')    # folder-open
set -l IC_DICE (printf '\uf522')      # dice
set choice (gum choose --cursor "$IC_POINTER" --header "Pick your vibe (hellwal)" \
    "$IC_FOLDER Pick Wallpaper" "$IC_DICE Random Wallpaper")

set start_ms (date +%s%3N)
set -g wallpaper_paths (load_wallpapers)
set end_ms (date +%s%3N)
set elapsed_ms (math "$end_ms - $start_ms")
set elapsed_sec (math -s2 "$elapsed_ms / 1000")
echo -e "$IC_ACC$IC_CLOCK$IC_RESET  \033[1;33m[Load Wallpapers List]\033[0m took \033[1;32m\"$elapsed_sec\"s\033[0m (\"$elapsed_ms\"ms)"

set -g wallpaper ""

switch $choice
    case "$IC_FOLDER Pick Wallpaper"
        set start_ms (date +%s%3N)
        set wallpaper (env \
            MESA_DEBUG_OVERRIDE=0 \
            MESA_LOG_LEVEL=0 \
            GSK_RENDERER=gl \
            VK_INSTANCE_LAYERS= \
            VK_LAYER_PATH= \
            python3 ~/Projects/wallmat/src/main.py "$wallpaper_dir" --plain 2>/dev/null | string trim)
        set end_ms (date +%s%3N)
        set elapsed_ms (math "$end_ms - $start_ms")
        set elapsed_sec (math -s2 "$elapsed_ms / 1000")
        echo -e "$IC_ACC$IC_CLOCK$IC_RESET  \033[1;33m[Wallpaper Picker App]\033[0m took \033[1;32m\"$elapsed_sec\"s\033[0m (\"$elapsed_ms\"ms)"

    case "$IC_DICE Random Wallpaper"
        if test (count $wallpaper_paths) -gt 0
            set wallpaper (random choice $wallpaper_paths)
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

# 1. Fire off wallpaper update in the background simultaneously with hellwal
run_apply_wallpaper "$wallpaper" &
set -l wallpaper_pid $last_pid

# 2. Run hellwal Theme Generation, guarded against no-op re-runs.
# A repeat run with the SAME wallpaper (path+mtime) and mode skips the template
# regeneration entirely. Delete ~/.cache/hellwal/last_theme_run to force a full
# regeneration (or the token is invalidated on any real change).
set -l last_run_file "$HOME/.cache/hellwal/last_theme_run"
set -l wp_mtime (stat -c %Y "$wallpaper" 2>/dev/null; or echo 0)
set -l token "$wallpaper|$wp_mtime|$mode"
if test -f "$last_run_file"
    and string match -q -- "$token" (string trim (cat "$last_run_file"))
    echo -e "$IC_ACC$IC_BOLT$IC_RESET Accent unchanged ($wallpaper) — skipping hellwal Theme Gen."
else
    set -l hellwal_mode (test "$mode" = "light"; and echo --light; or echo --dark)
    time_block "Hellwal Theme Gen" $HELLWAL_CMD -i "$wallpaper" $hellwal_mode --skip-term-colors
    mkdir -p "$HOME/.cache/hellwal"
    echo "$token" > "$last_run_file"
    # Stage hellwal roles where the shared icon/cursor scripts expect them,
    # so folder/grad/cursor recoloring uses the hellwal accent (last run wins).
    cp -f ~/.config/hellwal/hellwal-colors.css ~/.config/matugen/matugen-colors.css
    # Templates just rewritten — reload apps in parallel (duration prints when done)
    run_bg_timed "App Reloads" ~/.config/matugen/post-hook-scripts/reload-apps.sh
end

# Ensure wallpaper application has fully completed before moving forward
wait $wallpaper_pid

# 3. Trigger all independent background sync/icon hooks concurrently
run_folder_icons
run_cursor_icons
run_sync_zen_boost

# Run core GNOME settings
time_block "GNOME Settings Engine" run_hellwal_gnome_settings

run_sync_darkreader

# 4. Final layout hook — MUST run after the folder-icon recolor completes.
if test -n "$FOLDER_ICONS_PID"
    wait $FOLDER_ICONS_PID 2>/dev/null
end
time_block "Hellwal Merge Layout Hook" bash "/home/sakib/.config/matugen/post-hook-scripts/merge-layout.sh"

echo "Applied theme for: $mode"

sleep 0.3
rm -f $DARKMODE_LOCK

set pipeline_end (date +%s%3N)
set total_ms (math "$pipeline_end - $pipeline_start")
set total_sec (math -s2 "$total_ms / 1000")

echo -e "\n$IC_ACC$IC_FLAG$IC_RESET \033[1;36m[TOTAL PIPELINE TIME]\033[0m: \033[1;32m\"$total_sec\"s\033[0m (\"$total_ms\"ms)"