#!/usr/bin/env fish
# theme-lib.fish
# Shared config + all theming functions. Source this from either entrypoint
# (theme-picker.fish for interactive use, darkmode-watcher.fish for the
# background dark/light toggle watcher). Sourcing this file never blocks
# on input and never runs anything by itself.

# ======================
# ⚙️ CONFIG
# ======================
set -g wallpaper_dir "/mnt/Storage/Wallpapers"
set -g spinner "globe"  # Valid options: line, dot, minidot, jump, pulse, points, globe, moon, monkey, meter, hamburger
set -g colors_dir ~/.config/colors
set -g cache_file ~/.cache/current-wallpaper
set -g lock_file ~/.cache/theme-pipeline.lock

# ======================
# 🌓 MODE DETECTION
# ======================
function current_mode
    set raw_scheme (gsettings get org.gnome.desktop.interface color-scheme)
    if string match -q "*prefer-dark*" $raw_scheme
        echo "dark"
    else
        echo "light"
    end
end

# ======================
# 🖼️ WALLPAPER
# ======================
function load_wallpapers
    find $wallpaper_dir -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' \)
end

function save_current_wallpaper -a wallpaper
    mkdir -p (path dirname $cache_file)
    echo $wallpaper > $cache_file
end

function apply_wallpaper -a wallpaper
    set filename (path basename $wallpaper)

    gum spin --spinner $spinner --title "Applying wallpaper to GNOME..." -- fish -c "
        gsettings set org.gnome.desktop.background picture-uri 'file://$wallpaper'
        gsettings set org.gnome.desktop.background picture-uri-dark 'file://$wallpaper'
    "

    echo "🖼️ Wallpaper set to: $filename"
end

# ======================
# 🎨 MATUGEN
# ======================
function generate_theme -a wallpaper mode
    # matugen image $wallpaper -t scheme-content --show-colors
    # matugen image $wallpaper -t scheme-expressive --show-colors
    matugen image $wallpaper -t scheme-fidelity --mode $mode
    # matugen image $wallpaper -t scheme-fruit-salad --show-colors
    # matugen image $wallpaper -t scheme-monochrome --show-colors
    # matugen image $wallpaper -t scheme-neutral --show-colors
    # matugen image $wallpaper -t scheme-rainbow --show-colors
end

function set_folder_icons
    gum spin --spinner moon --title "Setting folder icon theme..." -- ~/Scripts/folder_icon.sh
end

# ======================
# 🎛️ GNOME EXTENSIONS / SHELL
# ======================
function apply_gnome_settings
    # --- pop shell / o-tiling ---
    set pop_hint_color (cat $colors_dir/pop-shell.css | string trim)
    dconf write /org/gnome/shell/extensions/pop-shell/hint-color-rgba "'$pop_hint_color'"
    dconf write /org/gnome/shell/extensions/o-tiling/hint-color-rgba "'$pop_hint_color'"

    # --- clock ---
    set clock_file $colors_dir/clock-color.css
    set time_rgba (sed -n '1p' $clock_file)
    set date_rgba (sed -n '2p' $clock_file)
    set cmd_rgba  (sed -n '3p' $clock_file)
    set hint_rgba (sed -n '4p' $clock_file)

    dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/time-font-color "'$time_rgba'"
    dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/date-font-color "'$date_rgba'"
    dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/command-output-font-color "'$cmd_rgba'"
    dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/hint-font-color "'$hint_rgba'"

    # --- SPACE BAR ---
    set space_file $colors_dir/space-bar.css

    while read -l line
        set line (string trim $line)

        string match -q "#*" $line; and continue
        test -z "$line"; and continue

        set parts (string split '=' $line)
        set key (string trim $parts[1])
        set value (string trim $parts[2])

        switch $key
            case active_bg
                set active_bg $value
            case active_fg
                set active_fg $value
            case inactive_fg
                set inactive_fg $value
        end
    end < $space_file

    dconf write /org/gnome/shell/extensions/space-bar/appearance/active-workspace-background-color $active_bg
    dconf write /org/gnome/shell/extensions/space-bar/appearance/active-workspace-text-color $active_fg
    dconf write /org/gnome/shell/extensions/space-bar/appearance/inactive-workspace-text-color $inactive_fg

    # --- search-light ---
    python ~/Scripts/normalize_rgb.py

    set search_file $colors_dir/search-light.css
    set foreground ""
    set background ""

    while read -l line
        set line (string trim $line)
        string match -q "#*" $line; and continue
        test -z "$line"; and continue

        set parts (string split '=' $line)
        set key (string trim $parts[1])
        set value (string trim $parts[2])

        switch $key
            case foreground; set foreground $value
            case background; set background $value
        end
    end < $search_file

    dconf write /org/gnome/shell/extensions/search-light/background-color "($background, 0.75)"
    dconf write /org/gnome/shell/extensions/search-light/text-color "($foreground, 1.0)"
    dconf write /org/gnome/shell/extensions/search-light/panel-icon-color "($foreground, 1.0)"
    dconf write /org/gnome/shell/extensions/search-light/border-color "($foreground, 1.0)"

    # --- Dynamic Music Pill ---
    set color_file $colors_dir/search-light.css

    set fg_line (sed -n '1p' $color_file)
    set bg_line (sed -n '2p' $color_file)

    set fg_vals (string split ", " (string replace "foreground = " "" $fg_line))
    set bg_vals (string split ", " (string replace "background = " "" $bg_line))

    set fg_rgb (math "round($fg_vals[1] * 255)")","(math "round($fg_vals[2] * 255)")","(math "round($fg_vals[3] * 255)")
    set bg_rgb (math "round($bg_vals[1] * 255)")","(math "round($bg_vals[2] * 255)")","(math "round($bg_vals[3] * 255)")

    dconf write /org/gnome/shell/extensions/dynamic-music-pill/custom-text-color "'$fg_rgb'"
    dconf write /org/gnome/shell/extensions/dynamic-music-pill/custom-bg-color "'$bg_rgb'"

    set clean_bg (string replace -a "'" "" $active_bg)
    bash ~/Scripts/choose-accent.sh "$clean_bg"

    # set yazi color
    # python3 ~/Scripts/yazi-theme.py
end

# ======================
# 🌐 DARK READER SYNC
# ======================
function sync_darkreader
    set DB "/home/sakib/.zen/oup922t1.Default (release)/storage-sync-v2.sqlite"

    set BG (jq -r '.colors.color0' ~/.config/colors.json)
    set FG (jq -r '.colors.color13' ~/.config/colors.json)

    sqlite3 $DB "
    UPDATE storage_sync_data
    SET data = json_set(
        data,
        '\$.theme.darkSchemeBackgroundColor', '$BG',
        '\$.theme.darkSchemeTextColor', '$FG',
        '\$.theme.scrollbarColor', '$FG'
    )
    WHERE ext_id = 'addon@darkreader.org';
    "
end

# ======================
# 🚀 ZEN BOOST SYNC
# ======================
function sync_zen_boost
    if test -f ~/Scripts/update-boost.js
        node ~/Scripts/update-boost.js
    else
        echo "⚠️ update-boost.js not found in matugen script directory"
    end
end

# ======================
# 🚀 PIPELINE
# ======================
function run_theme_pipeline -a wallpaper mode
    generate_theme $wallpaper $mode
    set_folder_icons
    apply_gnome_settings
    sync_darkreader
    sync_zen_boost
    bash "/home/sakib/.config/matugen/post-hook-scripts/merge-layout.sh"

    echo "Applied theme for: $mode"
end

# Wraps run_theme_pipeline with a lock file so matugen's own post-hook
# (which flips color-scheme light->dark->light to force a GTK redraw)
# can't retrigger the darkmode watcher and cause an infinite loop.
function run_theme_pipeline_locked -a wallpaper mode
    touch $lock_file
    run_theme_pipeline $wallpaper $mode
    sleep 0.5
    rm -f $lock_file
end
