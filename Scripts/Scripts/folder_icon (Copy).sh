#!/usr/bin/env fish

# 1. Grab Matugen accent + on_primary colors
set target_hex (grep -oP -- '--primary:\s*\K#[0-9a-fA-F]+' ~/.config/matugen/matugen-colors.css | head -1)
set on_primary_hex (grep -oP -- '--on_primary:\s*\K#[0-9a-fA-F]+' ~/.config/matugen/matugen-colors.css | head -1)
test -n "$target_hex"; and test -n "$on_primary_hex"; or exit 1

set theme_dir ~/.icons/Tela-Hybrid

# 2. Fast Targeted Recolor
function recolor_theme -a dir hex on_primary
    if test -d $dir
        set sample (find $dir -path "*/places/*.svg" -print -quit)
        or return

        set old_hex (grep -ozP 'ColorScheme-Highlight\s*\{\s*color:\s*\K#[0-9a-fA-F]+' $sample | tr '\0' '\n' | head -1)
        or return

        # Emblem/logo color (ColorScheme-Background). Only scalable has it.
        set bg_sample (find $dir/scalable -path "*/places/*.svg" -print -quit 2>/dev/null)
        set old_bg_hex ""
        if test -n "$bg_sample"
            set old_bg_hex (grep -ozP 'ColorScheme-Background\s*\{\s*color:\s*\K#[0-9a-fA-F]+' $bg_sample | tr '\0' '\n' | head -1)
        end

        cd $dir
        find . -type f -path "*/places/*.svg" -print0 | xargs -0 -P (nproc) sed -i "s/$old_hex/$hex/gI"

        if test -n "$old_bg_hex"
            # Only CSS class defs use `color:` — the hardcoded `fill="#ffffff"` tab stays untouched.
            find . -type f -path "*/places/*.svg" -print0 | xargs -0 -P (nproc) sed -i "s/color:$old_bg_hex/color:$on_primary/gI"
        end

        gtk-update-icon-cache -f -t $dir 2>/dev/null
        gtk4-update-icon-cache -f -t $dir 2>/dev/null
    end
end

# 3. Recolor theme
recolor_theme $theme_dir $target_hex $on_primary_hex

# 4. Instant UI Refresh
gsettings set org.gnome.desktop.interface icon-theme 'Adwaita'
gsettings set org.gnome.desktop.interface icon-theme 'Tela-Hybrid'