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

# ======================
# ⏱️ BENCHMARK HELPER
# ======================
function time_block -a name
    set -l start_ms (date +%s%3N)
    
    # Execute passed command or function natively
    $argv[2..-1]
    
    set -l end_ms (date +%s%3N)
    set -l elapsed_ms (math "$end_ms - $start_ms")
    set -l elapsed_sec (math -s2 "$elapsed_ms / 1000")
    
    echo -e "⏱️  \033[1;33m[$name]\033[0m took \033[1;32m{$elapsed_sec}s\033[0m ({$elapsed_ms}ms)"
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
    
    echo "🖼️ Wallpaper set to: $filename"
end

# Run a script in the background but print its REAL elapsed time once it
# completes (the pipeline keeps going; the line appears when the job is done).
function run_bg_timed -a name script
    set -l start_ms (date +%s%3N)
    bash $script &>/dev/null &
    set -l pid $last_pid

    begin
        wait $pid 2>/dev/null
        set -l end_ms (date +%s%3N)
        set -l elapsed_ms (math "$end_ms - $start_ms")
        set -l elapsed_sec (math -s2 "$elapsed_ms / 1000")
        echo -e "⏱️  \033[1;33m[$name]\033[0m took \033[1;32m{$elapsed_sec}s\033[0m ({$elapsed_ms}ms)"
    end &
end

function run_folder_icons
    set -l script_dir (path dirname (status --current-filename))
    set -g FOLDER_ICONS_PID ""
    set -l start_ms (date +%s%3N)
    bash $script_dir/folder_icon.sh &>/dev/null &
    set -g FOLDER_ICONS_PID $last_pid

    # Report real duration in the background (pipeline keeps going).
    begin
        wait $FOLDER_ICONS_PID 2>/dev/null
        set -l end_ms (date +%s%3N)
        set -l elapsed_ms (math "$end_ms - $start_ms")
        set -l elapsed_sec (math -s2 "$elapsed_ms / 1000")
        echo -e "⏱️  \033[1;33m[Folder Icons]\033[0m took \033[1;32m{$elapsed_sec}s\033[0m ({$elapsed_ms}ms)"
    end &
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

    # --- Accent chooser ---
    set -l primary "$MC_primary"
    if test -n "$primary"
        set -l clean_bg (string replace -a "'" "" "$primary")
        bash ~/Scripts/choose-accent.sh "$clean_bg" &>/dev/null &
    end
end

# function run_sync_darkreader
#     set -l DB "/home/sakib/.zen/ke09ovgb.myuser/storage-sync-v2.sqlite"
# 
#     if test -f $DB
#         load_matugen_colors; or return
#         set -l BG "$MC_background"
#         set -l FG "$MC_primary"
# 
#         if test -n "$BG"; and test -n "$FG"
#             sqlite3 $DB "
#             UPDATE storage_sync_data
#             SET data = json_set(
#                 data,
#                 '\$.theme.darkSchemeBackgroundColor', '$BG',
#                 '\$.theme.darkSchemeTextColor', '$FG',
#                 '\$.theme.scrollbarColor', '$FG'
#             )
#             WHERE ext_id = 'addon@darkreader.org';
#             " &>/dev/null
#         end
#     end
# end

# function run_sync_zen_boost
#     set -l script_dir (path dirname (status --current-filename))
# 
#     if test -f "$script_dir/update-boost.js"
#         node "$script_dir/update-boost.js" &>/dev/null
#     else
#         echo "⚠️ update-boost.js not found in script directory"
#     end
# end

# ======================
# 🎛️ MAIN MENU
# ======================
set choice (gum choose --cursor "👉" --header "Pick your vibe" \
    "📂 Pick Wallpaper" "🎲 Random Wallpaper")

# Load wallpaper list directly while timing
set start_ms (date +%s%3N)
set -g wallpaper_paths (load_wallpapers)
set end_ms (date +%s%3N)
set elapsed_ms (math "$end_ms - $start_ms")
set elapsed_sec (math -s2 "$elapsed_ms / 1000")
echo -e "⏱️  \033[1;33m[Load Wallpapers List]\033[0m took \033[1;32m{$elapsed_sec}s\033[0m ({$elapsed_ms}ms)"

set -g wallpaper ""

switch $choice
    case "📂 Pick Wallpaper"
        set start_ms (date +%s%3N)
        set wallpaper (env \
            MESA_DEBUG_OVERRIDE=0 \
            MESA_LOG_LEVEL=0 \
            GSK_RENDERER=gl \
            VK_INSTANCE_LAYERS= \
            VK_LAYER_PATH= \
            python3 ~/Scripts/wallpicker.py "$wallpaper_dir" 2>&1 | string trim)
        set end_ms (date +%s%3N)
        set elapsed_ms (math "$end_ms - $start_ms")
        set elapsed_sec (math -s2 "$elapsed_ms / 1000")
        echo -e "⏱️  \033[1;33m[Wallpaper Picker App]\033[0m took \033[1;32m{$elapsed_sec}s\033[0m ({$elapsed_ms}ms)"

    case "🎲 Random Wallpaper"
        if test (count $wallpaper_paths) -gt 0
            set wallpaper (random choice $wallpaper_paths)
        end
end

if test -z "$wallpaper"
    echo "⚠️ No wallpaper selected or folder is empty. Exiting."
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

# 2. Run Matugen Theme Generation
time_block "Matugen Theme Gen" matugen image "$wallpaper" --type scheme-smart --mode $mode

# Ensure wallpaper application has fully completed before moving forward
wait $wallpaper_pid

# 3. Trigger all independent background sync/icon hooks concurrently
# (real duration is reported by each job itself, once it completes)
run_folder_icons
run_cursor_icons

# Run core GNOME settings
time_block "GNOME Settings Engine" run_gnome_settings

# 4. Final layout hook — MUST run after the folder-icon recolor completes.
# The shell reload repaints the dash/grid; if it fires mid-swap it caches a
# random mix of old/new icon colors. Wait for the recolor first so the shell
# only ever sees the final, fully-swapped theme.
if test -n "$FOLDER_ICONS_PID"
    wait $FOLDER_ICONS_PID 2>/dev/null
end
time_block "Matugen Merge Layout Hook" bash "/home/sakib/.config/matugen/post-hook-scripts/merge-layout.sh"

echo "Applied theme for: $mode"

sleep 0.3
rm -f $DARKMODE_LOCK

set pipeline_end (date +%s%3N)
set total_ms (math "$pipeline_end - $pipeline_start")
set total_sec (math -s2 "$total_ms / 1000")

echo -e "\n🏁 \033[1;36m[TOTAL PIPELINE TIME]\033[0m: \033[1;32m{$total_sec}s\033[0m ({$total_ms}ms)"
