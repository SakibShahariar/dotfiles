#!/bin/bash

# Function to confirm user choice
confirm_action() {
    local message=$1
    gum style --border normal --padding "1" --border-foreground 10 "$message"
    local choice=$(gum choose "Yes, Proceed" "Skip this step" "Cancel Setup")
    
    case "$choice" in
        "Cancel Setup")
            echo "Setup canceled."
            exit 1
            ;;
        "Skip this step")
            return 1
            ;;
        "Yes, Proceed")
            return 0
            ;;
    esac
}

# Enable Copr repositories for Zen Browser and Ghostty
confirm_action "Enable Copr repositories for Zen Browser and Ghostty?" && {
    sudo dnf copr enable -y sneexy/zen-browser
    sudo dnf copr enable -y pgdev/ghostty
}

# Install priority apps first
confirm_action "Install priority apps like Zen Browser, GNOME Tweaks, and Extension Manager?" && {
    sudo dnf install -y zen-browser gnome-tweaks gnome-shell-extension-manager
}

# Install essential packages and perform system upgrades
confirm_action "Upgrade system groups and perform firmware update?" && {
    sudo dnf group upgrade -y core
    sudo dnf upgrade -y

    sudo fwupdmgr refresh --force
    sudo fwupdmgr get-updates
    sudo fwupdmgr update
}

# Switch to full FFMPEG and upgrade multimedia packages
confirm_action "Switch to full FFMPEG and upgrade multimedia packages?" && {
    sudo dnf swap -y 'ffmpeg-free' 'ffmpeg' --allowerasing
    sudo dnf group upgrade -y multimedia
    sudo dnf install -y ffmpeg-libs libva libva-utils intel-media-driver
}

# Install additional essential packages
confirm_action "Install additional packages like Kitty, MPV, and others?" && {
    sudo dnf install -y kitty mpv neovim htop ripgrep
}

# System performance tweaks
confirm_action "Apply system performance tweaks (CPU mitigations/network)?" && {
    sudo grubby --update-kernel=ALL --args="mitigations=off"
    sudo systemctl disable NetworkManager-wait-online.service
    sudo rm -f /etc/xdg/autostart/org.gnome.Software.desktop
}

# Install GNOME Extensions via package manager
GNOME_EXTENSION_PACKAGES=(
    gnome-shell-extension-user-theme
    gnome-shell-extension-appindicator
    gnome-shell-extension-gsconnect
)

confirm_action "Install GNOME Extensions from official repositories?" && {
    sudo dnf install -y "${GNOME_EXTENSION_PACKAGES[@]}"
}

# Post-install recommendations
cat <<-EOF
$(gum style --border normal --padding "1" --border-foreground 11 "✅ Setup Completed!")
