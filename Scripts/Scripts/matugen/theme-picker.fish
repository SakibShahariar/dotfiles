#!/usr/bin/env fish
# theme-picker.fish
# Interactive entrypoint: pick (or randomize) a wallpaper, then apply the
# full theme pipeline. Run this by hand / from a launcher or keybind.

source ~/Scripts/matugen/theme-lib.fish

# ======================
# 🎛️ MAIN MENU
# ======================
set choice (gum choose --cursor "👉" --header "Pick your vibe" \
    "📂 Pick Wallpaper" "🎲 Random Wallpaper")

set wallpaper_paths (load_wallpapers)

switch $choice
    case "📂 Pick Wallpaper"

        set wallpaper (env \
            MESA_DEBUG_OVERRIDE=0 \
            MESA_LOG_LEVEL=0 \
            GSK_RENDERER=gl \
            VK_INSTANCE_LAYERS= \
            VK_LAYER_PATH= \
            python3 ~/Scripts/wallpicker.py "$wallpaper_dir" 2>/dev/null | string trim)

        if test -z "$wallpaper"
            echo "No wallpaper selected, exiting."
            exit 1
        end

    case "🎲 Random Wallpaper"
        set wallpaper (random choice $wallpaper_paths)
end

set mode (current_mode)

# ======================
# 🚀 EXECUTION
# ======================
if test -n "$wallpaper"
    apply_wallpaper $wallpaper
    save_current_wallpaper $wallpaper
    run_theme_pipeline_locked $wallpaper $mode
end
