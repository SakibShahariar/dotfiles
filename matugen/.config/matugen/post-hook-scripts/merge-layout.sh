#!/usr/bin/env bash
set -euo pipefail

T="$HOME/.themes/Material-Gnome/gnome-shell"

# 1. Component Verification
if [ ! -f "$T/gnome-shell-stub.css" ]; then
    echo "❌ CRITICAL ERROR: Base stub missing at $T/gnome-shell-stub.css"
    exit 1
fi

if [ ! -f "$T/layouts/active-layout.css" ]; then
    echo "❌ CRITICAL ERROR: Active layout missing at $T/layouts/active-layout.css"
    exit 1
fi

# 2. Fast Compile GNOME Shell Theme
# Merge files with guaranteed newline separation - TWO empty lines between files
{
    cat "$T/gnome-shell-stub.css"
    printf '\n'
    printf '\n'
    cat "$T/layouts/active-layout.css"
} > "$T/gnome-shell.css"

# 3. Non-Blocking Reload
# Prefer the forked user-theme extension's D-Bus Reload(): one Main.loadTheme()
# call, no settings churn. Falls back to the old disable/sleep/enable toggle
# until the fork is loaded (after the next login).
if command -v gdbus &> /dev/null && gdbus call --session --dest org.gnome.Shell \
        --object-path /org/sakib/ThemeReload \
        --method org.sakib.ThemeReload.Reload >/dev/null 2>&1; then
    :
elif command -v gnome-extensions &> /dev/null; then
    (
        EXT='user-theme@gnome-shell-extensions.gcampax.github.com'
        # Skip when the extension is not active: there is no theme to reload,
        # and we must not silently enable it for the user.
        gnome-extensions list --enabled 2>/dev/null | grep -qxF "$EXT" || exit 0
        trap 'gnome-extensions enable "$EXT" &>/dev/null || true' EXIT INT TERM
        gnome-extensions disable "$EXT" &>/dev/null
        sleep 0.1
        gnome-extensions enable "$EXT" &>/dev/null
    ) &
    disown
fi
