#!/usr/bin/fish

# Step 1: Extract hex color from line 25 of colors.json
set colors_file ~/.config/colors.json
set line (sed -n '25p' $colors_file)
set hex (echo $line | string match -r '#[a-fA-F0-9]{6}')

if test -z "$hex"
    echo "Error: Could not extract hex color from line 25"
    exit 1
end

# Step 2: Call Python for the complex color math
set nearest_color (python3 -c "
import sys
import colorsys
import math

hex_color = sys.argv[1]

# Tela color definitions (name, hex)
tela_colors = {
    'Tela-nord': '#4d576a',
    'Tela-grey': '#bdbdbd',
    'Tela-purple': '#7e57c2',
    'Tela-brown': '#795548',
    'Tela': '#5294e2',
    'Tela-red': '#ef5350',
    'Tela-manjaro': '#16a085',
    'Tela-orange': '#e18908',
    'Tela-blue': '#5677fc',
    'Tela-pink': '#f06292',
    'Tela-ubuntu': '#fb8441',
    'Tela-green': '#66bb6a',
    'Tela-dracula': '#44475a',
    'Tela-yellow': '#ffca28',
}

def hex_to_hsl(hex_color):
    hex_color = hex_color.lstrip('#')
    r, g, b = tuple(int(hex_color[i:i+2], 16)/255.0 for i in (0, 2, 4))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    return (h*360, s, l)

def color_distance(hsl1, hsl2):
    # Weighted HSL distance with hue priority
    dh = min(abs(hsl1[0] - hsl2[0]), 360 - abs(hsl1[0] - hsl2[0])) / 180.0
    ds = abs(hsl1[1] - hsl2[1])
    dl = abs(hsl1[2] - hsl2[2])
    return 0.7*dh + 0.2*ds + 0.1*dl

input_hsl = hex_to_hsl(hex_color)
min_distance = float('inf')
nearest_color = ''

for name, tela_hex in tela_colors.items():
    tela_hsl = hex_to_hsl(tela_hex)
    distance = color_distance(input_hsl, tela_hsl)
    if distance < min_distance:
        min_distance = distance
        nearest_color = name

print(nearest_color)
" $hex)

# Step 3: Set global icon theme using gsettings
if test -n "$nearest_color"
    echo "Setting icon theme to: $nearest_color"

    if not command -q gsettings
        echo "Error: gsettings command not found. Are you on GNOME?"
        exit 1
    end

    gsettings set org.gnome.desktop.interface icon-theme "$nearest_color"
    set current_theme (gsettings get org.gnome.desktop.interface icon-theme | string trim -c "'")
    echo "Icon theme changed to: $current_theme $hex"
else
    echo "Error: Could not determine nearest icon theme"
    exit 1
end
