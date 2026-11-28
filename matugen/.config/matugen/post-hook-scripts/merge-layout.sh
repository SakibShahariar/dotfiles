#!/usr/bin/env bash
set -euo pipefail

# gnome-shell.css is generated directly by matugen (and the other color
# generators) with `@import url("layouts/active-layout.css");` at the top,
# so there is no stub/layout merge step here anymore. Just reload the shell.

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
