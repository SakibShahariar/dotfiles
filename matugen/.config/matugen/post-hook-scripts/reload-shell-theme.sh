#!/usr/bin/env bash
set -euo pipefail

# Merge the generated base stylesheet with the selected layout. @import was
# tried and dropped: imported stylesheets don't inherit extension priority
# (GNOME Shell issue #9415), so some rules stopped applying. The merge costs
# ~6ms and keeps all rules directly loaded in the right cascade order.
T="$HOME/.themes/Material-Gnome/gnome-shell"
if [ ! -f "$T/gnome-shell-stub.css" ] || [ ! -f "$T/layouts/active-layout.css" ]; then
    echo "❌ CRITICAL: base or active layout missing" >&2
    exit 1
fi
{
    cat "$T/gnome-shell-stub.css"
    printf '\n'
    printf '\n'
    cat "$T/layouts/active-layout.css"
} > "$T/gnome-shell.css"

if command -v gnome-extensions &> /dev/null; then
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
