#!/usr/bin/env bash

# Configuration
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
LOG_FILE="$XDG_CACHE_HOME/gowall-process.log"
BASE_DIR="/mnt/sda4/Wallpaper"
#BASE_DIR="/home/sakib/Pictures/dark"

# Suppress all terminal output
exec 2> /dev/null
exec > /dev/null

# Environment variables to suppress GPU warnings
export MESA_GLSL_CACHE_DISABLE=1
export ANV_DISABLE_DRM_FORMAT_MODIFIERS=1
export GDK_BACKEND=x11

# Create log directory if missing
mkdir -p "$(dirname "$LOG_FILE")"

show_error() {
    zenity --error --width=400 --text="$1" --title="Error"
    exit 1
}

check_dependencies() {
    local dependencies=("zenity" "gowall" "find" "basename")
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            show_error "Missing required command: $cmd"
        fi
    done
}

select_theme() {
    local themes=(
        "arcdark" "atomdark" "catppuccin" "cyberpunk" "dracula"
        "everforest" "github-light" "gruvbox" "material" "monokai"
        "night-owl" "nord" "oceanic-next" "onedark" "rose-pine"
        "shades-of-purple" "solarized" "srcery" "sunset-aurant"
        "sunset-saffron" "sunset-tangerine" "synthwave-84"
        "tokyo-dark" "tokyo-moon" "tokyo-storm"
    )

    zenity --list \
        --title="Select Theme" \
        --width=400 \
        --height=600 \
        --text="Select a theme from the list:" \
        --column="Available Themes" \
        "${themes[@]}" || exit 0
}

verify_base_dir() {
    [ -d "$BASE_DIR" ] || show_error "Wallpaper directory not found:\n$BASE_DIR"
}

process_images() {
    local theme="$1"
    verify_base_dir
    
    zenity --info --width=400 --text="Using wallpaper directory:\n<b>$BASE_DIR</b>" --title="Directory Selected"

    # Find image files
    local image_files=()
    while IFS= read -r -d $'\0' file; do
        image_files+=("$file")
    done < <(find "$BASE_DIR" -type f \( \
        -iname "*.png" -o \
        -iname "*.jpg" -o \
        -iname "*.jpeg" -o \
        -iname "*.gif" -o \
        -iname "*.bmp" -o \
        -iname "*.webp" \) -print0)

    [ ${#image_files[@]} -gt 0 ] || show_error "No image files found in:\n$BASE_DIR"

    local total=${#image_files[@]}
    local pipe=$(mktemp -u)
    mkfifo "$pipe"
    exec 3<>"$pipe"

    zenity --progress \
        --title="Processing Images" \
        --text="Starting..." \
        --percentage=0 \
        --auto-close \
        --width=600 <&3 &
    local zenity_pid=$!

    cleanup() { exec 3>&-; rm -f "$pipe"; kill $zenity_pid 2>/dev/null; }
    trap cleanup EXIT

    for ((current=1; current<=total; current++)); do
        kill -0 $zenity_pid 2>/dev/null || break
        percentage=$((100 * current / total))
        echo "$percentage" >&3
        echo "# Processing item $current of $total" >&3
        MESA_GLSL_CACHE_DISABLE=1 ANV_DISABLE_DRM_FORMAT_MODIFIERS=1 \
            gowall convert "${image_files[$current-1]}" -t "$theme" >> "$LOG_FILE" || break
    done

    [ $current -gt $total ] && echo "100" >&3 || \
        show_error "Processing canceled!\nStopped after $((current-1))/$total files."
}

main() {
    check_dependencies
    theme=$(select_theme)
    process_images "$theme"
    zenity --info --width=400 \
        --text="✅ All images processed successfully!\n\nTheme: <b>$theme</b>" \
        --title="Processing Complete"
}

main
