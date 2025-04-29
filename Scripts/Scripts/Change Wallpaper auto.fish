#!/usr/bin/env fish

# Directory containing wallpapers
set wallpaper_dir "/home/sakib/Wallpaper"

# Interval between wallpaper changes (in seconds)
set interval 1200  # 20 minutes

# Get the list of wallpapers
set wallpapers (find $wallpaper_dir -type f \( -iname "*.jpg" -o -iname "*.png" \))

# Check if the directory contains any wallpapers
if test (count $wallpapers) -eq 0
    echo "No wallpapers found in $wallpaper_dir"
    exit 1
end

# Infinite loop to change wallpaper
while true
    # Pick a random wallpaper
    set wallpaper (printf "%s\n" $wallpapers | shuf -n 1)

    # Debug: Show the selected wallpaper
    echo "Setting wallpaper: $wallpaper"

    # Set the wallpaper for dark mode
    gsettings set org.gnome.desktop.background picture-uri-dark "file://$wallpaper" 2>> /home/sakib/WallpaperChange.log
    
    # Set the wallpaper display option (zoom)
    gsettings set org.gnome.desktop.background picture-options "zoom" 2>> /home/sakib/WallpaperChange.log

    # Wait for the specified interval
    sleep $interval
end
