#!/usr/bin/env bash
set -euo pipefail

T="$HOME/.themes/Material-Gnome/gnome-shell"

# 1. Component Verification
if [ ! -f "$T/gnome-shell-stub.css" ] || [ ! -f "$T/layouts/active-layout.css" ]; then
    echo "❌ CRITICAL ERROR: Theme components missing at $T"
    exit 1
fi

# 2. Fast Compile GNOME Shell Theme
cat "$T/gnome-shell-stub.css" "$T/layouts/active-layout.css" > "$T/gnome-shell.css"

# 3. Non-Blocking Reload (Background Subshell)
if command -v dconf &> /dev/null; then
    (
        dconf write /org/gnome/shell/extensions/user-theme/name "'default'"
        sleep 0.1
        dconf write /org/gnome/shell/extensions/user-theme/name "'Material-Gnome'"
    ) &>/dev/null &
    disown
fi