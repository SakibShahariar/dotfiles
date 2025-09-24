#!/usr/bin/env fish

# ======================
# Configuration
# ======================
set wallpaper_dir "/mnt/data/Wallpapers"
set spinner "globe"  # Valid options: line, dot, minidot, jump, pulse, points, globe, moon, monkey, meter, hamburger

# ======================
# Helper Functions
# ======================

function load_wallpapers
    # Find all wallpaper files asynchronously
    # Supports JPG, PNG, JPEG formats
    find $wallpaper_dir -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' \) &
    wait
end

function apply_wallpaper -a wallpaper
    # Extract just the filename for display
    set filename (basename $wallpaper)

    # Show spinner while applying (GNOME specific)
    gum spin --spinner $spinner --title "Applying wallpaper to GNOME..." -- fish -c "
        # Set for both light and dark modes
        gsettings set org.gnome.desktop.background picture-uri 'file://$wallpaper'
        gsettings set org.gnome.desktop.background picture-uri-dark 'file://$wallpaper'
    "

    echo "🖼️ Wallpaper set to: $filename"
end

function generate_theme -a wallpaper
    # Generate multiple theme variants with matugen
    # Main vibrant theme (most commonly used)
    matugen image $wallpaper -v --show-colors
    # matugen image $wallpaper --show-colors
    # matugen image $wallpaper

    # Other available schemes (commented out by default)
    # matugen image $wallpaper -t scheme-content --show-colors
    # matugen image $wallpaper -t scheme-expressive --show-colors
    # matugen image $wallpaper -t scheme-fidelity --show-colors
    # matugen image $wallpaper -t scheme-fruit-salad --show-colors
    # matugen image $wallpaper -t scheme-monochrome --show-colors
    # matugen image $wallpaper -t scheme-neutral --show-colors
    # matugen image $wallpaper -t scheme-rainbow --show-colors

    # Apply colors to kitty terminal
    kitty @ set-colors --all ~/.config/kitty/themes/colors.conf

end

function set_folder_icons
    # Get directory of this script to find the icon script
    set script_dir (dirname (status --current-filename))

    # Show spinner while setting folder icons
    gum spin --spinner moon --title "Setting folder icon theme..." -- $script_dir/folder_icon.fish
end

function apply_gnome_settings
    # This trick forces GNOME to reload the theme

    dconf write /org/gnome/shell/extensions/user-theme/name "'default'"
    dconf write /org/gnome/shell/extensions/user-theme/name "'Material-Gnome'"

    # Apply accent color to Pop Shell

    set pop_hint_color (cat ~/.config/colors/pop-shell.css | string trim)

    dconf write /org/gnome/shell/extensions/pop-shell/hint-color-rgba "'$pop_hint_color'"

    # Apply the same color to clock extension elements

    set rgba (cat ~/.config/colors/accent-color.css | string trim)

    for key in time-font-color date-font-color hint-font-color command-output-font-color
        dconf write /org/gnome/shell/extensions/customize-clock-on-lockscreen/$key "'$rgba'"
    end

    # Space Bar Extension: Apply colors from file

    set color_file ~/.config/colors/space-bar.css

    # Read each line and assign variables
    for line in (cat $color_file | string trim | grep -v '^#')
        set parts (echo $line | string split '=')
        set key (string trim $parts[1])
        set value (string trim $parts[2])

        switch $key
            case 'active_bg'
                set active_bg $value
            case 'active_fg'
                set active_fg $value
            case 'inactive_fg'
                set inactive_fg $value
        end
    end

    # Write to Space Bar dconf keys
    dconf write /org/gnome/shell/extensions/space-bar/appearance/active-workspace-background-color $active_bg

    dconf write /org/gnome/shell/extensions/space-bar/appearance/active-workspace-text-color $active_fg

    dconf write /org/gnome/shell/extensions/space-bar/appearance/inactive-workspace-text-color $inactive_fg

    # Search-light Extension: Apply colors from file

    # normalized the colors
    python ~/Scripts/normalize_rgb.py

    set color_file ~/.config/colors/search-light.css

    # Read each line and assign variables
    for line in (cat $color_file | string trim | grep -v '^#')
        set parts (echo $line | string split '=')
        set key (string trim $parts[1])
        set value (string trim $parts[2])

        switch $key
            case 'foreground'
                set foreground $value
            case 'background'
                set background $value
        end
    end

    # Write to Search Light dconf keys
    dconf write /org/gnome/shell/extensions/search-light/background-color "($background, 0.75)"

    dconf write /org/gnome/shell/extensions/search-light/text-color "($foreground, 1.0)"

    dconf write /org/gnome/shell/extensions/search-light/panel-icon-color "($foreground, 1.0)"

end

# ======================
# Main Script
# ======================

# Show selection menu with gum
# Custom cursor and header for better UX
set choice (gum choose --cursor "👉" --header "Pick your vibe" \
    "📂 Pick Wallpaper" "🎲 Random Wallpaper")

# Load wallpapers in background (async)
set wallpaper_paths (load_wallpapers)

switch $choice
    case "📂 Pick Wallpaper"
        # Default: Python wallpicker (current)
        set wallpaper (env \
            MESA_DEBUG_OVERRIDE=0 \
            MESA_LOG_LEVEL=0 \
            MESA_DEBUG_DISABLE=vulkan \
            VK_INSTANCE_LAYERS= \
            VK_LAYER_PATH= \
            python3 ~/Scripts/wallpicker.py 2>/dev/null | string trim)

        # Alternative: Zenity/Nautilus file picker (uncomment to use)
        # set wallpaper (zenity --file-selection \
        #     --title="Select a Wallpaper" \
        #     --file-filter="*.jpg *.jpeg *.png" \
        #     --filename="$wallpaper_dir/")

        # Exit if user cancels selection
        if test -z "$wallpaper"
            echo "No wallpaper selected, exiting."
            exit 1
        end

    case "🎲 Random Wallpaper"
        # Pick random wallpaper from the found paths
        set wallpaper (random choice $wallpaper_paths)
end

if test -n "$wallpaper"
    # Apply all changes in sequence:
    # 1. Set the wallpaper
    # 2. Generate color scheme
    # 3. Update folder icons
    # 4. Apply GNOME settings
    apply_wallpaper $wallpaper
    generate_theme $wallpaper
    set_folder_icons
    apply_gnome_settings
end
