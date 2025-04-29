#!/usr/bin/env fish

# Function to simulate typewriter effect
function typewrite
    set message $argv[1]
    for i in (string split "" $message)
        echo -n $i
        sleep 0.01
    end
    echo
end

# Where the art lives
set WALLPAPER_DIR "/mnt/data/Wallpapers" 

# Summon one random masterpiece
set IMAGE (find $WALLPAPER_DIR -type f \( -iname \*.jpg -or -iname \*.png -or -iname \*.jpeg \) | shuf -n 1)
echo

# Show confirmation with the selected wallpaper
typewrite (set_color green; echo "✔ Wallpaper selected: $IMAGE"; set_color normal)
echo

# Set wallpaper for both light and dark modes in GNOME
typewrite (set_color yellow; echo "🌈 Setting your wallpaper... Please wait..."; set_color normal)
gsettings set org.gnome.desktop.background picture-uri "file://$IMAGE"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$IMAGE"
echo

# Generate color palette from the selected image
typewrite (set_color yellow; echo "🎨 Generating a color palette from your wallpaper..."; set_color normal)
#matugen image "$IMAGE"
set dominant_color (matugen image "$IMAGE" --json hex | jq -r '.colors.dark.primary')

# Run wal without applying colors
# wal -i "$IMAGE" -s -t -n

# Print the dominant color for debugging
echo "Dominant color: $dominant_color"
echo

# Apply new colors
typewrite (set_color blue; echo "🌟 Applying the new colors..."; set_color normal)
kitty @ set-colors --all ~/.config/kitty/colors.conf
echo

# Call folder.py and pass the dominant color
typewrite (set_color cyan; echo "🔍 Matching color to Tela theme..."; set_color normal)
set icon_theme (python3 $HOME/Scripts/folder_color.py $dominant_color)

# Show the icon theme suggested by check.py
echo "Suggested Icon Theme: $icon_theme"
echo

# Apply the icon theme in GNOME
typewrite (set_color green; echo "🎨 Applying the icon theme..."; set_color normal)
gsettings set org.gnome.desktop.interface icon-theme "$icon_theme"

# Check if the gsettings command was successful
if test $status -ne 0
    echo "❌ Failed to apply icon theme"
    exit 1
end

echo

fish ~/Scripts/remove_hash.fish

# Final success message with a little excitement
typewrite (set_color green; echo "🎉 Done! Enjoy your fresh wallpaper, colors, and icon theme!"; set_color normal)
