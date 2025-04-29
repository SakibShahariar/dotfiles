#!/bin/bash

# Configuration
WALLPAPERS_DIR="/mnt/sda4/Wallpapers"
GENERATE_SCRIPT="/home/sakib/Scripts/generate_colors.py"

# Check dependencies
if ! command -v wal &> /dev/null; then
    echo "Error: 'wal' (pywal) not found in PATH" >&2
    exit 1
fi

# Check directories
if [ ! -d "$WALLPAPERS_DIR" ]; then
    echo "Error: Wallpapers directory not found: $WALLPAPERS_DIR" >&2
    exit 1
fi

# Get random wallpaper with full path
IMAGE=$(find "$WALLPAPERS_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0 | shuf -n1 -z | xargs -0 realpath)
if [ -z "$IMAGE" ]; then
    echo "Error: No image files found in $WALLPAPERS_DIR" >&2
    exit 1
fi

# Generate colors with wal
echo "󰆧 Generating colors from: ${IMAGE##*/}"
echo

if ! wal -i "$IMAGE"; then
    echo "Error: pywal failed to generate colors" >&2
    exit 1
fi

# Apply color scheme to templates
echo
echo " Processing templates..."
echo
if ! python3 "$GENERATE_SCRIPT"; then
    echo "Error: Template generation failed" >&2
    exit 1
fi

# Set GNOME wallpaper
echo "󰉏 Setting wallpaper..."
gsettings set org.gnome.desktop.background picture-uri "file://$IMAGE"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$IMAGE"

echo -e "\n󰄭 Wallpaper and colors updated successfully!"
echo
echo "󰏘 New wallpaper: ${IMAGE/#$HOME/\~}"
