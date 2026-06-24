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

# 2. Compile GNOME Shell Theme
cat "$T/gnome-shell-stub.css" "$T/layouts/active-layout.css" > "$T/gnome-shell.css"

# 3. Reload Shell Theme via Wayland-safe dconf toggling
if command -v dconf &> /dev/null; then
    # Unload current user theme to default
    dconf write /org/gnome/shell/extensions/user-theme/name "'default'"
    sleep 0.2

    # Load your updated theme compilation
    dconf write /org/gnome/shell/extensions/user-theme/name "'Material-Gnome'"

    # --- CRUCIAL WAYLAND FIX ---
    # We must wait here for 1 full second to let GNOME Shell freeze and
    # finish rebuilding its UI assets BEFORE this script finishes executing.
    sleep 1.0

    # Now that the freeze is over, aggressively drain the buffered ghost keys
    if [ -t 0 ] || [ -c /dev/tty ]; then
        stty echo 2>/dev/null || true
        while read -t 0.1 -n 10000 < /dev/tty; do :; done 2>/dev/null || true
    fi
else
    echo "⚠️ Warning: 'dconf' command not found. Theme was compiled but not reloaded."
fi
