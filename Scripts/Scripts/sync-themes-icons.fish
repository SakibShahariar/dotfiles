#!/usr/bin/env fish

function log_success
    set_color green
    echo -e "✅ $argv"
    set_color normal
end

function log_skip
    set_color yellow
    echo -e "⏭️  $argv"
    set_color normal
end

function log_info
    set_color blue
    echo -e "🎯 $argv"
    set_color normal
end

log_info "Linking GTK themes from ~/.themes to /usr/share/themes"
for theme in ~/.themes/*
    set name (basename $theme)
    if test -d $theme
        if not test -e /usr/share/themes/$name
            sudo ln -s $theme /usr/share/themes/$name
            log_success "Linked theme: $name"
        else
            log_skip "Theme exists: $name"
        end
    end
end

log_info "Linking icon themes from ~/.icons to /usr/share/icons"
for icon in ~/.icons/*
    set name (basename $icon)
    if test -d $icon
        if not test -e /usr/share/icons/$name
            sudo ln -s $icon /usr/share/icons/$name
            log_success "Linked icon: $name"
        else
            log_skip "Icon exists: $name"
        end
    end
end

log_info "✨ Done syncing themes and icons!"
