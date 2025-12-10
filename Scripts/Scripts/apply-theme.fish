#!/usr/bin/env fish

# This script applies a matugen theme based on a provided theme name.
# It does NOT handle wallpaper selection or application.

# ======================
# Configuration
# ======================
set spinner "globe"  # Valid options: line, dot, minidot, jump, pulse, points, globe, moon, monkey, meter, hamburger

# ======================
# Helper Functions
# ======================

function generate_theme -a theme_name
    set theme_json_path (string join "" ~/.config/matugen/themes/ $theme_name ".json")

    if not test -f "$theme_json_path"
        echo "Error: Theme JSON file not found: $theme_json_path"
        exit 1
    end

    # Generate theme from JSON file with matugen
    gum spin --spinner $spinner --title "Generating theme from $theme_name..." -- fish -c "
        matugen json $theme_json_path --show-colors
    "

    # Apply colors to kitty terminal
    kitty @ set-colors --all ~/.config/kitty/themes/colors.conf
end

function set_wallpaper -a theme_name
    set config_file ~/.config/matugen/wallpaper_map.json
    if not test -f "$config_file"
        echo "Warning: Wallpaper mapping file not found at $config_file"
        return
    end

    # Check if jq is installed
    if not command -v jq >/dev/null
        echo "Error: 'jq' is not installed. Please install it to use wallpaper mapping."
        return
    end

    set wallpaper_path (jq -r ".\"$theme_name\"" "$config_file")

    if test -z "$wallpaper_path" -o "$wallpaper_path" = "null"
        echo "Warning: Wallpaper for theme '$theme_name' not found in $config_file"
        return
    end

    if not test -f "$wallpaper_path"
        echo "Warning: Wallpaper file not found at '$wallpaper_path'"
        return
    end

    # Set wallpaper using dconf
    gum spin --spinner moon --title "Setting wallpaper..." -- fish -c "
        dconf write /org/gnome/desktop/background/picture-uri \"'file://$wallpaper_path'\"
        dconf write /org/gnome/desktop/background/picture-uri-dark \"'file://$wallpaper_path'\"
    "
end

function set_folder_icons
    # Path to the icon script is assumed to be in ~/Scripts
    set icon_script_path (string join "" ~/Scripts/folder_icon.sh)

    if not test -f "$icon_script_path"
        echo "Warning: Folder icon script not found at $icon_script_path"
        return
    end

    # Show spinner while setting folder icons
    gum spin --spinner moon --title "Setting folder icon theme..." -- $icon_script_path
end

function apply_gnome_settings
    # This trick forces GNOME to reload the theme

    dconf write /org/gnome/shell/extensions/user-theme/name "'default'"
    dconf write /org/gnome/shell/extensions/user-theme/name "'Material-Gnome'"

    # Apply accent color to Pop Shell

    set pop_hint_color (cat ~/.config/colors/pop-shell.css | string trim)

    dconf write /org/gnome/shell/extensions/pop-shell/hint-color-rgba "'$pop_hint_color'"

    # Apply the same color to clock extension elements

    set rgba (cat ~/.config/colors/accent-color.css | string trim)

    for key in time-font-color date-font-color hint-font-color command-output-font-color
        dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/$key "'$rgba'"
    end

    # Space Bar Extension: Apply colors from file

    set color_file ~/.config/colors/space-bar.css

    # Read each line and assign variables
    for line in (cat $color_file | string trim | grep -v '^#')
        set parts (echo $line | string split '=')
        set key (string trim $parts[1])
        set value (string trim $parts[2])

        switch $key
            case 'active_bg'
                set active_bg $value
            case 'active_fg'
                set active_fg $value
            case 'inactive_fg'
                set inactive_fg $value
        end
    end

    # Write to Space Bar dconf keys
    dconf write /org/gnome/shell/extensions/space-bar/appearance/active-workspace-background-color $active_bg

    dconf write /org/gnome/shell/extensions/space-bar/appearance/active-workspace-text-color $active_fg

    dconf write /org/gnome/shell/extensions/space-bar/appearance/inactive-workspace-text-color $inactive_fg

    # Search-light Extension: Apply colors from file

    # normalized the colors
    python ~/Scripts/normalize_rgb.py

    set color_file ~/.config/colors/search-light.css

    # Read each line and assign variables
    for line in (cat $color_file | string trim | grep -v '^#')
        set parts (echo $line | string split '=')
        set key (string trim $parts[1])
        set value (string trim $parts[2])

        switch $key
            case 'foreground'
                set foreground $value
            case 'background'
                set background $value
        end
    end

    # Write to Search Light dconf keys
    dconf write /org/gnome/shell/extensions/search-light/background-color "($background, 0.75)"

    dconf write /org/gnome/shell/extensions/search-light/text-color "($foreground, 1.0)"

    dconf write /org/gnome/shell/extensions/search-light/panel-icon-color "($foreground, 1.0)"

    dconf write /org/gnome/shell/extensions/search-light/border-color "($foreground, 1.0)"

    # remove quotes around hex if present
    set clean_bg (string replace -a "'" "" $active_bg)
    bash ~/Scripts/choose-accent.sh "$clean_bg"

end

# ======================
# Main Script
# ======================

# Check if a theme name is provided
if test -z "$argv[1]"
    echo "Usage: apply-theme.fish <theme_name>"
    exit 1
end

set selected_theme_name "$argv[1]"

# Apply all changes in sequence:
# 1. Generate color scheme from JSON
# 2. Set the wallpaper
# 3. Update folder icons
# 4. Apply GNOME settings
generate_theme $selected_theme_name
set_wallpaper $selected_theme_name
set_folder_icons
apply_gnome_settings
