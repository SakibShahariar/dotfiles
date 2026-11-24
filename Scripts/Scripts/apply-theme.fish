#!/usr/bin/env fish

# Apply a pre-generated matugen theme (JSON) by name.
# Mirrors matugen.fish's pipeline: same helpers, same output format, same
# concurrency, but the scheme comes from ~/.config/matugen/themes/*.json
# instead of an image, and the wallpaper is picked from wallpaper_map.json.

# ======================
# ⚙️ CONFIG
# ======================
set -g DARKMODE_LOCK /tmp/.dark-mode-self-toggle.lock
set -g THEMES_DIR ~/.config/matugen/themes
set -g WALLPAPER_MAP ~/.config/matugen/wallpaper_map.json
set -g WALLPAPER_DIR /mnt/Storage/Wallpapers
set -g HOOKS_DIR ~/.config/matugen/post-hook-scripts

function _cleanup_lock --on-event fish_exit
    rm -f $DARKMODE_LOCK
end

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
# ⏱️ BENCHMARK HELPERS
# ======================
# Print the duration between $start_ms and now. Optionally waits for a PID
# first, so the number is the job's REAL runtime, not just its launch cost.
function print_time -a name start_ms pid
    if test -n "$pid"
        wait $pid 2>/dev/null
    end
    set -l end_ms (date +%s%3N)
    set -l elapsed_ms (math "$end_ms - $start_ms")
    set -l elapsed_sec (math -s2 "$elapsed_ms / 1000")
    echo -e "$IC_ACC$IC_CLOCK$IC_RESET  \033[1;33m[$name]\033[0m took \033[1;32m\"$elapsed_sec\"s\033[0m (\"$elapsed_ms\"ms)"
end

function time_block -a name
    set -l start_ms (date +%s%3N)
    $argv[2..-1]
    print_time $name $start_ms
end

# ======================
# 🧰 NATIVE PIPELINE FUNCTIONS
# ======================
function run_apply_wallpaper -a img_path
    set -l filename (path basename "$img_path")
    cp "$img_path" ~/.config/background.jpg

    gsettings set org.gnome.desktop.background picture-uri "file://$img_path"
    gsettings set org.gnome.desktop.background picture-uri-dark "file://$img_path"

    echo -e "$IC_ACC$IC_IMAGE$IC_RESET Wallpaper set to: $filename"
end

function start_folder_icons
    set -l script_dir (path dirname (status --current-filename))
    set -l theme (gsettings get org.gnome.desktop.interface icon-theme | tr -d "'")
    switch $theme
        case Material-Grad
            bash $script_dir/grad_icon.sh &>/dev/null &
        case '*'
            bash $script_dir/folder_icon.sh &>/dev/null &
    end
    set -g FOLDER_ICONS_PID $last_pid
end

function start_cursor_icons
    set -l script_dir (path dirname (status --current-filename))
    bash $script_dir/cursor_matugen.sh &>/dev/null &
    set -g CURSOR_ICONS_PID $last_pid
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

    # --- O-Tiling ---
    set -l color (mc_rgba primary 0.5)
    test -n "$color"; and dconf write /org/gnome/shell/extensions/o-tiling/hint-color-rgba "'$color'"

    # --- Clock (lockscreen) ---
    dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/time-font-color "'"(mc_rgba primary 1)"'"
    dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/date-font-color "'"(mc_rgba on_surface_variant 1)"'"
    dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/command-output-font-color "'"(mc_rgba secondary 1)"'"
    dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/hint-font-color "'"(mc_rgba surface_variant 1)"'"

    # --- Dynamic Music Pill ---
    dconf write /org/gnome/shell/extensions/dynamic-music-pill/sync-accent-color "true"
    set -l fg_rgb (mc_rgb primary)
    set -l bg_rgb (mc_rgb surface)
    dconf write /org/gnome/shell/extensions/dynamic-music-pill/custom-text-color "'$fg_rgb'"
    dconf write /org/gnome/shell/extensions/dynamic-music-pill/custom-bg-color "'$bg_rgb'"

    # --- Accent chooser (backgrounded, awaited at the end of the pipeline) ---
    set -l primary "$MC_primary"
    if test -n "$primary"
        set -l clean_bg (string replace -a "'" "" "$primary")
        bash ~/Scripts/choose-accent.sh "$clean_bg" &>/dev/null &
        set -g ACCENT_PID $last_pid
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

function generate_theme -a theme_name mode
    set -l suffix dark
    test "$mode" = "dark"; or set suffix light

    # Theme files come in several flavours: "{Name}-Dark.json", the newer
    # "{name}-dark.json" / "{name}-dark-high-contrast.json" / "{name}-amoled.json",
    # and one-off "{Name}.json". Match case-insensitively, preferring the file
    # that matches the current mode, then an exact "{name}.json".
    set -l theme_json_path ""
    for candidate in "$theme_name-$suffix.json" "$theme_name.json"
        set -l hit (find "$THEMES_DIR" -maxdepth 1 -type f -iname "$candidate" 2>/dev/null | head -1)
        if test -n "$hit"
            set theme_json_path $hit
            break
        end
    end

    if test -z "$theme_json_path"
        echo "Error: Theme JSON file not found for '$theme_name' ($mode) in $THEMES_DIR"
        exit 1
    end

    gum spin --spinner $spinner --title "Generating theme from $theme_name ($mode)..." -- \
        matugen json "$theme_json_path"
end

# ======================
# 🎛️ MAIN ENTRY POINT
# ======================
if test -z "$argv[1]"
    echo "Usage: apply-theme.fish <theme_name> [wallpaper_path]"
    exit 1
end

set selected_theme_name "$argv[1]"

# Detect mode safely
set raw_scheme (gsettings get org.gnome.desktop.interface color-scheme)
if string match -q "*prefer-dark*" $raw_scheme
    set -g mode "dark"
else
    set -g mode "light"
end

# Resolve the wallpaper: explicit override wins, else a random entry from the
# theme's map (skipping entries whose files no longer exist). Variant themes
# such as "vhs-dark" / "vhs-light" inherit their family's wallpapers, and
# themes added after the map was written fall back to the wallpaper pool.
set wallpaper "$argv[2]"
if test -z "$wallpaper"; and test -f "$WALLPAPER_MAP"
    set -l lookups $selected_theme_name
    set -l family (string replace -r -- '-(dark|light)(-high-contrast|-amoled)?$' '' $selected_theme_name)
    if test "$family" != "$selected_theme_name"
        set -a lookups $family
    end

    for lookup in $lookups
        set -l mapped (jq -r ".\"$lookup\".wallpapers[]" "$WALLPAPER_MAP" 2>/dev/null)
        set -l valid
        for w in $mapped
            test -f "$w"; and set -a valid $w
        end
        if test (count $valid) -gt 0
            set wallpaper $valid[(random 1 (count $valid))]
            break
        end
    end
end

if test -z "$wallpaper"
    set -l pool (find $WALLPAPER_DIR -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) 2>/dev/null)
    if test (count $pool) -gt 0
        set wallpaper (random choice $pool)
        echo -e "$IC_ACC$IC_WARN$IC_RESET No wallpaper mapped for '$selected_theme_name' — picked one from the pool."
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

# 1. Fire off wallpaper update in the background simultaneously with Matugen
run_apply_wallpaper "$wallpaper" &
set -l wallpaper_pid $last_pid

# 2. Generate templates from the theme JSON
time_block "Matugen Theme Gen" generate_theme $selected_theme_name $mode

# Ensure wallpaper application has fully completed before moving forward
wait $wallpaper_pid

# 3. Trigger all independent background sync/icon hooks concurrently
# (their real durations are printed further down, once the work is done)
set -l folder_start (date +%s%3N)
start_folder_icons

set -l cursor_start (date +%s%3N)
start_cursor_icons

set -l zen_start (date +%s%3N)
run_sync_zen_boost &>/dev/null &
set -l zen_pid $last_pid

set -l darkreader_start (date +%s%3N)
run_sync_darkreader &>/dev/null &
set -l darkreader_pid $last_pid

# Run core GNOME settings
time_block "GNOME Settings Engine" run_gnome_settings

# 4. Reload applications (GTK themes, kitty, TUI signals) — backgrounded so the
# icon/text work continues, but awaited before the final timer.
set -l reload_start (date +%s%3N)
bash $HOOKS_DIR/reload-apps.sh &>/dev/null &
set -l reload_pid $last_pid

# 5. Final layout hook — MUST run after the folder-icon recolor completes.
# The shell reload repaints the dash/grid; if it fires mid-swap it caches a
# random mix of old/new icon colors. Wait for the recolor first so the shell
# only ever sees the final, fully-swapped theme.
print_time "Folder Icons" $folder_start $FOLDER_ICONS_PID
time_block "Matugen Merge Layout Hook" bash $HOOKS_DIR/merge-layout.sh

# 6. Drain every trailing job before reporting the total, so the printed
# pipeline time matches wall-clock time (no work survives the TOTAL line).
print_time "Cursor Icons" $cursor_start $CURSOR_ICONS_PID
print_time "App Reloads" $reload_start $reload_pid
wait $zen_pid 2>/dev/null
wait $darkreader_pid 2>/dev/null
if set -q ACCENT_PID
    wait $ACCENT_PID 2>/dev/null
end

echo "Applied theme for: $mode"

sleep 0.1
rm -f $DARKMODE_LOCK

set -l pipeline_end (date +%s%3N)
set -l total_ms (math "$pipeline_end - $pipeline_start")
set -l total_sec (math -s2 "$total_ms / 1000")

echo -e "\n$IC_ACC$IC_FLAG$IC_RESET \033[1;36m[TOTAL PIPELINE TIME]\033[0m: \033[1;32m\"$total_sec\"s\033[0m (\"$total_ms\"ms)"
