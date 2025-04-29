import sys
import webcolors
import math
import re
from colorsys import rgb_to_hsv

tela_colors = {
    "Tela-nord-dark": "#4d576a",
    "Tela-grey-dark": "#bdbdbd",
    "Tela-purple-dark": "#7e57c2",
    "Tela-brown-dark": "#795548",
    "Tela-dark": "#5294e2",
    "Tela-red-dark": "#ef5350",
    "Tela-manjaro-dark": "#16a085",
    "Tela-orange-dark": "#e18908",
    "Tela-blue-dark": "#5677fc",
    "Tela-pink-dark": "#f06292",
    "Tela-black-dark": "#4d4d4d",
    "Tela-ubuntu-dark": "#fb8441",
    "Tela-green-dark": "#66bb6a",
    "Tela-dracula-dark": "#44475a",
    "Tela-yellow-dark": "#ffca28",
    "Gruvbox-Plus-Dark": "#749185",
    "Gruvbox-tomato": "#fb4934",    
    "ZorinOrange-Dark": "#fcc8b4",    
    "ZorinOrange-Dark": "#fcc8b4",
    "ZorinGreen-Dark": "#bbf1dd",
    "ZorinBlue-Dark": "#bde6fb",
    "ZorinRed-Dark": "#fdb4b4",
    "ZorinPurple-Dark": "#d8c4f1",
    "Zorin": "#90a4ae",
}

def hex_to_hsv(hex_color):
    rgb = webcolors.hex_to_rgb(hex_color)
    r, g, b = [x / 255.0 for x in rgb]
    h, s, v = rgb_to_hsv(r, g, b)
    return h * 360, s, v  # Convert hue to degrees (0-360)

def calculate_hsv_distance(hsv1, hsv2):
    h1, s1, v1 = hsv1
    h2, s2, v2 = hsv2
    hue_distance = min(abs(h1 - h2), 360 - abs(h1 - h2)) / 180
    return math.sqrt(
        (8 * hue_distance) ** 2 +  # Reduced hue weighting for better matching
        (2 * (s1 - s2)) ** 2 +
        (1 * (v1 - v2)) ** 2
    )

def is_valid_hex_color(hex_color):
    hex_color_regex = r'^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$'
    return re.match(hex_color_regex, hex_color) is not None

# Get color from command-line argument
if len(sys.argv) < 2:
    print("Please provide a color as a command-line argument.")
    sys.exit(1)

user_color = sys.argv[1]

if not is_valid_hex_color(user_color):
    print("Invalid hex color code.")
    sys.exit(1)

# Convert user color to HSV
user_hsv = hex_to_hsv(user_color)

# Find the closest Tela color
closest_theme = None
min_distance = float('inf')

for theme_name, theme_hex in tela_colors.items():
    theme_hsv = hex_to_hsv(theme_hex)
    distance = calculate_hsv_distance(user_hsv, theme_hsv)
    if distance < min_distance:
        min_distance = distance
        closest_theme = theme_name        
       # print(f"QQ{closest_theme} {min_distance}")
    # else:
      #  print(f"QQ{closest_theme} {min_distance}")

print(f"{closest_theme}")
