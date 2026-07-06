#!/usr/bin/env fish
# File: ~/Scripts/qt_xcb_wrap.fish

# --- Dynamic Theme Integration ---
# Using ANSI color indices (1=Red/Error, 2=Green/Success, 4=Blue/Accent)

# Indicator with a gap for readability
set -x GUM_CHOOSE_CURSOR "➜ "
set -x GUM_CHOOSE_CURSOR_FOREGROUND "4"
set -x GUM_FILTER_INDICATOR "➜ "
set -x GUM_FILTER_INDICATOR_FOREGROUND "4"

# Text and Prompt Styling
set -x GUM_FILTER_PROMPT_FOREGROUND "4"
set -x GUM_FILTER_MATCH_FOREGROUND "4"
set -x GUM_FILTER_CURSOR_FOREGROUND "4"

# Standard color variables
set COLOR_SUCCESS "2"
set COLOR_ERROR "1"

# 1. Select Operation
set action (gum choose "Apply XCB Patch" "Revert Patch")

if test $status -ne 0
    exit 0
end

# 2. Fuzzy find an application
set app_name (ls /usr/share/applications | sed 's/\.desktop//' | gum filter --placeholder "Select an application...")

if test -z "$app_name"
    exit 0
end

set user_desktop $HOME/.local/share/applications/$app_name.desktop
set system_desktop /usr/share/applications/$app_name.desktop

# 3. Execution Logic
if test "$action" = "Revert Patch"
    if test -f "$user_desktop"
        if gum confirm "Are you sure you want to revert $app_name to default?"
            rm "$user_desktop"
            gum style --foreground $COLOR_SUCCESS "✔ Successfully reverted $app_name."
        end
    else
        gum style --foreground $COLOR_ERROR "✘ No patch found for $app_name."
    end

else if test "$action" = "Apply XCB Patch"
    if not test -f "$system_desktop"
        gum style --foreground $COLOR_ERROR "System .desktop file not found for $app_name."
        exit 1
    end

    mkdir -p $HOME/.local/share/applications
    cp $system_desktop $user_desktop
    
    # Backup original
    cp $user_desktop "$user_desktop.bak"
    
    # Patch
    sed -i "s|^Exec=|Exec=env QT_QPA_PLATFORM=xcb |" $user_desktop
    
    gum style --foreground $COLOR_SUCCESS "✔ Successfully patched $app_name to use XCB."
end