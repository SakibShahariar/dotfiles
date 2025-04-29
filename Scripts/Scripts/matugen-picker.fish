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

# Show the welcome message first
echo
typewrite (set_color cyan; echo "🖼️✨ Welcome to the Wallpaper Picker! 🎨"; set_color normal)
echo

# Set the default directory for wallpapers
set DEFAULT_DIR "/mnt/data/Wallpapers"

# Show a file picker with Zenity (no logs)
set IMAGE (zenity --file-selection --title="Pick a Wallpaper" --file-filter="Images | *.png *.jpg *.jpeg" --filename="$DEFAULT_DIR/" 2>/dev/null)

# Check if an image was selected, and exit if not
if test -z "$IMAGE"
    typewrite (set_color red; echo "❌ No image selected! Exiting..."; set_color normal)
    notify-send "Wallpaper Picker" "No image selected! Exiting..." --icon=dialog-error
    exit 1
end

# Show a confirmation with the selected wallpaper
typewrite (set_color green; echo "✔ Wallpaper selected: $IMAGE"; set_color normal)
echo

# Send a notification about wallpaper selection
notify-send "Wallpaper Picker" "Wallpaper selected: $IMAGE" --icon=dialog-information

# Set wallpaper for both light and dark modes in GNOME
typewrite (set_color yellow; echo "🌈 Setting your wallpaper... Please wait..."; set_color normal)
notify-send "Wallpaper Picker" "Setting your wallpaper..." --icon=dialog-information
gsettings set org.gnome.desktop.background picture-uri "file://$IMAGE"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$IMAGE"
echo

# Generate color palette from the selected image
typewrite (set_color yellow; echo "🎨 Generating a color palette from your wallpaper..."; set_color normal)
notify-send "Wallpaper Picker" "Generating color palette from your wallpaper..." --icon=dialog-information
set dominant_color (matugen image "$IMAGE" --json hex | jq -r '.colors.dark.primary')
echo

# Print the dominant color for debugging
echo "Dominant color: $dominant_color"
echo

# Apply new colors to Kitty terminal
typewrite (set_color blue; echo "🌟 Applying the new colors to Kitty..."; set_color normal)
notify-send "Wallpaper Picker" "Applying new colors to Kitty..." --icon=dialog-information
kitty @ set-colors --all ~/.config/kitty/colors.conf || typewrite (set_color red; echo "❌ Failed to apply Kitty colors!"; set_color normal)
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
typewrite (set_color green; echo "🎉 Done! Enjoy your fresh wallpaper and colors!"; set_color normal)
notify-send "Wallpaper Picker" "Done! Enjoy your fresh wallpaper and colors!" --icon=dialog-information
