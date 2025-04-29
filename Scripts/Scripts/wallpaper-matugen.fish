#!/usr/bin/env fish

# Function to simulate typewriter effect
function typewrite
    for i in (string split "" -- $argv)
        echo -n $i
        sleep 0.01  # Adjust speed of typing here
    end
    echo
end

# Open a file picker for the user to choose a wallpaper
set IMAGE (zenity --file-selection --title="Select a Wallpaper" --filename="/mnt/data/Wallpapers" --file-filter="Images | *.jpg *.png *.jpeg" 2>/dev/null)

# Check if the user selected a file
if test -z "$IMAGE"
    typewrite (set_color red; echo "❌ No wallpaper selected. Exiting..."; set_color normal)
    exit 1
end

echo

# Show confirmation with the selected wallpaper
typewrite (set_color green; echo "✔ Wallpaper selected: $IMAGE"; set_color normal)
echo

# Set wallpaper for both light and dark modes in GNOME
typewrite (set_color yellow; echo "🌈 Setting your wallpaper... Please wait..."; set_color normal)
gsettings set org.gnome.desktop.background picture-uri "file://$IMAGE"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$IMAGE"
if test $status -ne 0
    typewrite (set_color red; echo "❌ Failed to set wallpaper."; set_color normal)
    exit 1
end
echo

# Generate color palette from the selected image
typewrite (set_color yellow; echo "🎨 Generating a color palette from your wallpaper..."; set_color normal)
set dominant_color (matugen image "$IMAGE" --json hex | jq -r '.colors.dark.primary')

# Print the dominant color for debugging
echo "Dominant color: $dominant_color"
echo

# Apply new colors
typewrite (set_color blue; echo "🌟 Applying the new colors..."; set_color normal)
kitty @ set-colors --all ~/.config/kitty/colors.conf
echo

# Call check.py and pass the dominant color
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

# Final success message with a little excitement
typewrite (set_color green; echo "🎉 Done! Enjoy your fresh wallpaper, colors, and icon theme!"; set_color normal)
