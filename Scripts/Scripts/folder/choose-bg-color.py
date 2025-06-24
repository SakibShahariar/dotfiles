#!/usr/bin/env python3
import sys

def hex_to_rgb(hex_color: str):
    hex_color = hex_color.lstrip('#')
    return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))

def rgb_to_hex(rgb):
    return "#{:02x}{:02x}{:02x}".format(*rgb)

def brightness(rgb):
    r, g, b = rgb
    # Standard luminosity formula
    return 0.299 * r + 0.587 * g + 0.114 * b

def blend_colors(*colors):
    # colors are hex strings
    rgbs = [hex_to_rgb(c) for c in colors]
    count = len(rgbs)
    avg = tuple(
        round(sum(channel) / count) for channel in zip(*rgbs)
    )
    return rgb_to_hex(avg)

def choose_bg_color(color0, color8, color1, black="#000000"):
    b0 = brightness(hex_to_rgb(color0))

    if b0 < 10:
        b8 = brightness(hex_to_rgb(color8))
        if b8 < 10:
            b1 = brightness(hex_to_rgb(color1))
            if b1 > 90:
                return blend_colors(color0, color8, color1)
            else:
                return color1
        elif b8 > 90:
            return blend_colors(color0, color8)
        else:
            return color8
    elif b0 > 90:
        return blend_colors(color0, black)
    else:
        return color0

def preview_color(hex_color):
    r, g, b = hex_to_rgb(hex_color)
    # Print a block with bg color + the hex next to it
    block = f"\033[48;2;{r};{g};{b}m    \033[0m"
    print(f"Preview: {block} {hex_color}")

def main():
    # Your colors (replace with your wallpaper gen colors)
    color0 = "#00030b"
    color8 = "#030c30"
    color1 = "#272e5a"

    chosen = choose_bg_color(color0, color8, color1)
    preview_color(chosen)

    # For scripts: just print the hex code if you want to capture it
    print(chosen)

if __name__ == "__main__":
    main()
