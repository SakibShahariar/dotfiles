#!/bin/bash
# sync-extensions.sh (Fedora, Stow, & Gum Optimized)

# Configuration directory target (Stow handles mapping this to your repo)
CONFIG_DIR="$HOME/.config/gnome-extensions-sync"
LIST_FILE="$CONFIG_DIR/extensions.list"
DCONF_FILE="$CONFIG_DIR/settings.dconf"

# Ensure the config target directory exists
mkdir -p "$CONFIG_DIR"

# Ensure 'gum' and dependencies are installed (Fedora DNF)
if ! command -v gum &> /dev/null; then
    echo "📦 'gum' is required for the interactive menu. Installing via DNF..."
    sudo dnf install -y gum python3-pip pipx
fi

# -----------------------------------------------------------------------------
# BACKUP FUNCTION
# -----------------------------------------------------------------------------
backup_extensions() {
    echo "📦 Backing up GNOME extensions..."
    
    # 1. Save list of currently enabled extension UUIDs
    if ! gnome-extensions list --enabled > "$LIST_FILE" 2>/dev/null; then
        echo "⚠️  Warning: No active extensions found or 'gnome-extensions' utility missing."
        touch "$LIST_FILE"
    fi
    
    # 2. Dump dconf configuration profiles
    dconf dump /org/gnome/shell/extensions/ > "$DCONF_FILE"
    
    gum style --foreground 2 "✅ Backup complete! Data written through Stow symlink directly into your repo."
}

# -----------------------------------------------------------------------------
# RESTORE FUNCTION
# -----------------------------------------------------------------------------
restore_extensions() {
    # Verify Stow symlinks are active before running
    if [ ! -f "$LIST_FILE" ] || [ ! -f "$DCONF_FILE" ]; then
        gum style --foreground 1 "❌ Error: Backup configuration files missing. Please run 'stow' first!"
        exit 1
    fi

    echo "🚀 Initiating GNOME extensions restoration..."

    # Ensure gnome-extensions-cli is available
    if ! command -v gnome-extensions-cli &> /dev/null; then
        echo "📦 Installing 'gnome-extensions-cli' utility..."
        pipx ensurepath
        export PATH="$HOME/.local/bin:$PATH"
        pipx install gnome-extensions-cli --force
    fi

    # 2. Iterate and download extensions from the list
    if [ -s "$LIST_FILE" ]; then
        echo "📥 Downloading and installing extensions to user directory..."
        while IFS= read -r uuid || [ -n "$uuid" ]; do
            [[ -z "$uuid" || "$uuid" =~ ^# ]] && continue
            echo "   -> Fetching: $uuid"
            gnome-extensions-cli install "$uuid"
        done < "$LIST_FILE"
    else
        echo "ℹ️  No extensions found in your list to install."
    fi

    # 3. Inject configuration profiles into dconf
    echo "⚙️  Applying saved settings..."
    dconf load /org/gnome/shell/extensions/ < "$DCONF_FILE"

    gum style --foreground 2 "🎉 Restoration finished completely! Please log out and log back in to fully apply changes."
}

# -----------------------------------------------------------------------------
# INTERACTIVE GUM MENU
# -----------------------------------------------------------------------------
gum style --border normal --margin "1" --padding "1" --border-foreground 4 "🧬 GNOME Extension Sync Tool"

CHOICE=$(gum choose --cursor.foreground="4" "📦 Backup Current Setup" "🚀 Restore From Backup" "❌ Cancel")

case "$CHOICE" in
    "📦 Backup Current Setup")
        backup_extensions
        ;;
    "🚀 Restore From Backup")
        restore_extensions
        ;;
    *)
        echo "Exiting..."
        exit 0
        ;;
esac