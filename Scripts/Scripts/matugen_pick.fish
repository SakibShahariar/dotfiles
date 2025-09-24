#!/usr/bin/env fish

set wallpaper_dir "/mnt/data/Wallpapers"

# Call the Python picker silently and trim the result
set wallpaper (env MESA_DEBUG_OVERRIDE=0 MESA_LOG_LEVEL=0 MESA_DEBUG_DISABLE=vulkan VK_INSTANCE_LAYERS= VK_LAYER_PATH= python3 ~/Scripts/wallpicker.py 2>/dev/null | string trim)

# Exit silently if no wallpaper is selected
if test -z "$wallpaper"
    exit 0
end

# Apply the selected wallpaper
gsettings set org.gnome.desktop.background picture-uri "file://$wallpaper"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$wallpaper"

# Generate theme using matugen silently
matugen image $wallpaper -v > /dev/null 2>&1

# Reload kitty colors silently
kitty @ set-colors --all ~/.config/kitty/themes/colors.conf > /dev/null 2>&1

# Set folder icons
set script_dir (dirname (status --current-filename))
$script_dir/folder_icon.fish > /dev/null 2>&1

# Reset and reapply GNOME Shell theme
dconf write /org/gnome/shell/extensions/user-theme/name "'default'"
dconf write /org/gnome/shell/extensions/user-theme/name "'Material-Gnome'"

# Read RGBA from color.css
set pop_hint_color (cat ~/.config/colors/accent-color.css | string trim)

# Apply it to Pop Shell
dconf write /org/gnome/shell/extensions/pop-shell/hint-color-rgba "'$pop_hint_color'"

set rgba (cat ~/.config/colors/accent-color.css | string trim)

for key in time-font-color date-font-color hint-font-color command-output-font-color
    dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/$key "'$rgba'"
end

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
