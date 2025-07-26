#!/usr/bin/env fish

set wallpaper_dir "/mnt/data/Wallpapers"

# Call the Python picker silently and trim the result
set wallpaper (env MESA_DEBUG_OVERRIDE=0 MESA_LOG_LEVEL=0 MESA_DEBUG_DISABLE=vulkan VK_INSTANCE_LAYERS= VK_LAYER_PATH= python3 ~/Scripts/wallpicker.py $wallpaper_dir 2>/dev/null | string trim)

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
kitty @ set-colors --all ~/.config/kitty/colors.conf > /dev/null 2>&1

# Remove hash stuff
fish ~/Scripts/remove_hash.fish > /dev/null 2>&1

# Set folder icons
set script_dir (dirname (status --current-filename))
$script_dir/folder_icon.fish > /dev/null 2>&1

# Reset and reapply GNOME Shell theme
dconf write /org/gnome/shell/extensions/user-theme/name "'default'"
dconf write /org/gnome/shell/extensions/user-theme/name "'Material-Gnome'"
