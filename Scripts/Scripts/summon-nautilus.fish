#!/usr/bin/env fish

# Ensure wmctrl is present
type -q wmctrl; or begin
    echo "wmctrl is required but not installed."
    exit 1
end

# Get Nautilus window ID
set win_id (wmctrl -lx | grep -i "nautilus.Nautilus" | awk '{print $1}' | head -n 1)

if test -z "$win_id"
    # No window found, open new one
    nautilus --new-window &
else
    # Move and focus the existing window
    set cur_ws (wmctrl -d | grep '\*' | awk '{print $1}')
    wmctrl -i -r $win_id -t $cur_ws
    wmctrl -i -a $win_id
end
