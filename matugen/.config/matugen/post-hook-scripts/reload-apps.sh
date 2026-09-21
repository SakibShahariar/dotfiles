#!/usr/bin/env bash
# Fire every independent app reload concurrently after matugen renders
# templates. Each job is backgrounded; we wait for all of them so callers
# can report a real total duration.

jobs=()

# --- terminal / TUI reloads (signal-based, cheap) ---
pkill -USR2 btop || true &
jobs+=("$!")
pkill -USR1 cava || true &
jobs+=("$!")
pkill -USR1 clock-rs || true &
jobs+=("$!")

# --- fish colors trigger (universal var) ---
fish -c 'set -U MATUGEN_RELOAD_TRIGGER (date +%s)' &
jobs+=("$!")

# --- GTK3 theme re-apply ---
bash -c 'gsettings set org.gnome.desktop.interface gtk-theme ""; gsettings set org.gnome.desktop.interface gtk-theme "Material-Gnome"' &
jobs+=("$!")

# --- GTK4 theme reload (a11y high-contrast toggle) ---
"$HOME/.config/matugen/post-hook-scripts/gtk-themes-reload.sh" &
jobs+=("$!")

# --- kitty reload ---
kitty +kitten themes --reload-in=all Matugen &
jobs+=("$!")

wait "${jobs[@]}"