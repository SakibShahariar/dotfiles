#!/usr/bin/env bash
# ~/Scripts/folder_icon.sh - Fixed hue ranges

colors_file="$HOME/.config/colors.json"
line_number=25

raw_line=$(sed -n "${line_number}p" "$colors_file")
hex_input=$(echo "$raw_line" | grep -oE '#[A-Fa-f0-9]{6}' | tr '[:upper:]' '[:lower:]')

if [[ -z "$hex_input" ]]; then
    echo "Error: No hex color found on line $line_number" >&2
    exit 1
fi

echo "Input color: $hex_input"

nearest_color=$(python3 -c "
import colorsys

def hex_to_hsv(hex_color):
    hex_color = hex_color.lstrip('#')
    r = int(hex_color[0:2], 16) / 255.0
    g = int(hex_color[2:4], 16) / 255.0
    b = int(hex_color[4:6], 16) / 255.0
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    return h * 360, s * 100, v * 100

def smart_color_match(input_hex):
    hue, saturation, value = hex_to_hsv(input_hex)

    # Very low saturation colors are essentially grey
    if saturation < 15:
        return 'Tela-grey'

    # Improved hue ranges (consistent with accent script):
    # 0-15°: Red
    # 15-45°: Orange
    # 45-75°: Yellow
    # 75-165°: Green
    # 165-195°: Teal
    # 195-255°: Blue
    # 255-285°: Purple
    # 285-330°: Pink
    # 330-360°: Red

    if 285 <= hue <= 330:
        return 'Tela-pink'
    elif 255 <= hue < 285:
        return 'Tela-purple'
    elif 195 <= hue < 255:
        return 'Tela-blue'
    elif 165 <= hue < 195:
        return 'Tela-manjaro'
    elif 75 <= hue < 165:    # Green range expanded
        return 'Tela-green'
    elif 45 <= hue < 75:     # Yellow range narrowed
        return 'Tela-yellow'
    elif 15 <= hue < 45:
        return 'Tela-orange'
    else:  # 0-15° and 330-360°
        return 'Tela-red'

input_hex = '$hex_input'
hue, sat, val = hex_to_hsv(input_hex)

# Debug output to stderr
print(f'Debug: HSV({hue:.1f}°, {sat:.1f}%, {val:.1f}%)', file=__import__('sys').stderr)

# Get the match
match = smart_color_match(input_hex)
print(match)
")

if [[ $? -ne 0 || -z "$nearest_color" ]]; then
    echo "Error: Failed to calculate theme color" >&2
    exit 1
fi

echo "Nearest Tela color: $nearest_color"

# Apply via gsettings
if command -v gsettings > /dev/null; then
    echo "Applying icon theme: $nearest_color"
    if gsettings set org.gnome.desktop.interface icon-theme "$nearest_color"; then
        current_theme=$(gsettings get org.gnome.desktop.interface icon-theme | tr -d "'")
        echo "✓ Icon theme changed to: $current_theme"
    else
        echo "✗ Failed to apply icon theme" >&2
        exit 1
    fi
else
    echo "Note: gsettings not available (GNOME not detected?)"
fi
