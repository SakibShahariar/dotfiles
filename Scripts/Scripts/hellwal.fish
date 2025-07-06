#!/usr/bin/env fish

set wallpaper_dir "/mnt/data/Wallpapers"

# Show options immediately
set choice (gum choose --cursor "👉" --header "Pick your vibe" \
    "📂 Pick Wallpaper" "🎲 Random Wallpaper")

# Load wallpaper paths asynchronously
set wallpaper_paths (find $wallpaper_dir -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' \)) &

# Wait for wallpaper paths to be ready (without blocking the menu)
wait

# Create a mapping of basename to full path
set -l wallpaper_map
for path in $wallpaper_paths
    set filename (basename $path)
    set wallpaper_map $wallpaper_map $filename $path
end

switch $choice
    case "📂 Pick Wallpaper"
        # Use Zenity to invoke the Nautilus file picker, open in the correct dir
        set wallpaper (zenity --file-selection --title="Select a Wallpaper" --file-filter="*.jpg *.jpeg *.png" --filename="$wallpaper_dir/")

        # Exit if no wallpaper is selected
        if test -z "$wallpaper"
            echo "No wallpaper selected, exiting."
            exit 1
        end

        set filename (basename $wallpaper)
        echo "You picked: $filename"
    case "🎲 Random Wallpaper"
        # Pick a random wallpaper from the list
        set wallpaper (printf "%s\n" $wallpaper_paths | shuf -n 1)
        set filename (basename $wallpaper)
        echo "Random pick: $filename"
end

# Apply wallpaper with GNOME gsettings
if test -n "$wallpaper"
    gum spin --spinner globe --title "Applying wallpaper to GNOME..." -- fish -c "
        gsettings set org.gnome.desktop.background picture-uri 'file://$wallpaper';
        gsettings set org.gnome.desktop.background picture-uri-dark 'file://$wallpaper'
    "
    echo "🖼️ Wallpaper set to: $filename"

    # 🌈 Generate theme with hellwal
    hellwal -i $wallpaper

    # 🎨 Copy generated gtk.css to GTK 3 and GTK 4
    set hellwal_css ~/.cache/hellwal/gtk.css
    set hellwal_qt ~/.cache/hellwal/qt.conf
    set hellwal_kitty ~/.cache/hellwal/kitty.conf
    set hellwal_micro ~/.cache/hellwal/micro.micro
    set hellwal_mpv1 ~/.cache/hellwal/mpv-config.conf
    set hellwal_mpv2 ~/.cache/hellwal/mpv-uosc.conf
    set hellwal_pywalZen ~/.cache/hellwal/colors.json
    set hellwal_gtk_colors ~/.cache/hellwal/gtk-colors.css
    set hellwal_gtk3_colors ~/.cache/hellwal/gtk3-colors.css

    if test -f $hellwal_css
        cp $hellwal_css ~/.config/gtk-3.0/gtk.css
        # cp $hellwal_css ~/.config/gtk-4.0/gtk.css
        cp $hellwal_qt ~/.config/qt5ct/colors/colors.conf
        cp $hellwal_qt ~/.config/qt6ct/colors/colors.conf
        cp $hellwal_kitty ~/.config/kitty/colors.conf
        cp $hellwal_kitty ~/.config/kitty/colors.conf
        cp $hellwal_mpv1 ~/.config/mpv/mpv.conf
        cp $hellwal_mpv2 ~/.config/mpv/script-opts/uosc.conf
        cp $hellwal_pywalZen ~/.cache/wal/colors.json
        cp $hellwal_gtk_colors ~/.config/gtk-4.0/colors.css
        cp $hellwal_gtk_colors ~/.config/gtk-3.0/colors.css
        cp $hellwal_gtk_colors ~/.themes/Hellwal-GTK/gtk-4.0/colors.css
        cp $hellwal_gtk3_colors ~/.themes/Hellwal-GTK/gtk-3.0/colors.css
        cp $hellwal_gtk_colors ~/.zen/8myr0f8x.Default\ \(release\)/chrome/colors.css

        echo "🎨 gtk.css updated for GTK 3 and GTK 4"
    else
        echo "⚠️ hellwal gtk.css not found, skipping GTK theme update"
    end

    kitty @ set-colors --all ~/.config/kitty/colors.conf

        # ADDED: Call folder icon script after all other operations
    # Get directory of this script
    set script_dir (dirname (status --current-filename))

    # Execute folder_icon.fish from the same directory
    gum spin --spinner moon --title "Setting folder icon theme..." -- $script_dir/folder_icon.fish

end
