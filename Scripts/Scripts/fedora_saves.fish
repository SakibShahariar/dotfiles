#!/usr/bin/env fish

# ───🎨 UI Functions────────────────────────────────────────────────────
function run_cmd -d "Run command with visual feedback"
    set_color cyan
    echo "⏳ Running: $argv"
    set_color normal
    if not eval $argv
        set_color red
        echo "❌ Command failed: $argv"
        set_color normal
        return 1
    end
end

# ───📦 Dependencies────────────────────────────────────────────────────
function check_deps
    if not type -q gum
        echo "🚨 'gum' not found! Installing it..."
        run_cmd sudo dnf install -y gum || return 1
    end
end

# ───📡 Core System Functions───────────────────────────────────────────
function enable_repos
    # RPM Fusion
    if not dnf repolist | grep -q rpmfusion
        run_cmd sudo dnf install -y \
            https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
            https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
    end

    # Terra
    if not dnf repolist | grep -q terra
        run_cmd sudo dnf install -y --nogpgcheck \
            --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
            terra-release
    end

    # App Stream Metadata
    run_cmd sudo dnf group upgrade -y core
    run_cmd sudo dnf4 group install -y core
end

function system_update
    run_cmd sudo dnf -y update
    if gum confirm "Reboot recommended after updates. Reboot now?" --default=false
        reboot
    end
end

# ───🖥️ Hardware Configuration──────────────────────────────────────────
function firmware_update
    run_cmd sudo fwupdmgr refresh --force
    run_cmd sudo fwupdmgr get-devices
    run_cmd sudo fwupdmgr get-updates
    if gum confirm "Apply firmware updates now?" --affirmative="Yes" --negative="No"
        run_cmd sudo fwupdmgr update
    end
end

function nvidia_setup
    enable_repos
    run_cmd sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
    echo "🕒 Waiting for kernel module build (5 minutes)..."
    sleep 300
    if modinfo -F version nvidia
        echo "✅ NVIDIA module built successfully"
    else
        echo "❌ NVIDIA module build failed!"
    end
end

# ───📦 Software Management─────────────────────────────────────────────
function flatpak_setup
    if not flatpak remotes | grep -q flathub
        run_cmd flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    end
    if gum confirm "Install AppImage Manager (Gearlever)?" --default=true
        run_cmd flatpak install -y it.mijorus.gearlever
    end
end

function appimage_support
    run_cmd sudo dnf install -y fuse
end

# ───🔧 System Tweaks──────────────────────────────────────────────────
function media_codecs
    run_cmd sudo dnf swap -y 'ffmpeg-free' 'ffmpeg' --allowerasing
    run_cmd sudo dnf group install -y multimedia --setop="install_weak_deps=False"
    run_cmd sudo dnf group install -y sound-and-video
    run_cmd sudo dnf install -y gstreamer1-plugin-openh264 mozilla-openh264
end

function hw_acceleration
    run_cmd sudo dnf install -y libva-utils vdpauinfo
    echo "👉 For specific GPU configurations, please select your hardware:"
    set gpu_choice (gum choose "Intel" "AMD" "NVIDIA")
    switch $gpu_choice
        case "Intel"
            run_cmd sudo dnf install -y intel-media-driver
        case "AMD"
            run_cmd sudo dnf install -y mesa-va-drivers
        case "NVIDIA"
            echo "✅ NVIDIA drivers already handled in previous step"
    end
end

# ───🔒 System Configuration────────────────────────────────────────────
function network_config
    # Custom DNS
    if gum confirm "Configure Cloudflare DNS with DNS-over-TLS?"
        set dns_conf "[Resolve]\nDNS=1.1.1.2#security.cloudflare-dns.com 1.0.0.2#security.cloudflare-dns.com\nDNSOverTLS=yes"
        run_cmd echo $dns_conf | sudo tee /etc/systemd/resolved.conf.d/99-dns-over-tls.conf
        run_cmd sudo systemctl restart systemd-resolved
    end
    
    # NetworkManager tweaks
    run_cmd sudo systemctl disable NetworkManager-wait-online.service
end

function system_optimizations
    # Security/performance tradeoffs
    if gum confirm "Disable security mitigations for performance? (Not recommended)"
        run_cmd sudo grubby --update-kernel=ALL --args="mitigations=off"
    end
    
    # NVIDIA modeset
    if gum confirm "Enable NVIDIA modeset for PRIME support?"
        run_cmd sudo grubby --update-kernel=ALL --args="nvidia-drm.modeset=1"
    end
    
    # GNOME Software autostart
    run_cmd sudo rm -f /etc/xdg/autostart/org.gnome.Software.desktop
end

# ───🎨 Theming─────────────────────────────────────────────────────────
function install_themes
    if gum confirm "Install GTK themes?"
        run_cmd git clone https://github.com/lassekongo83/adw-gtk3
        run_cmd sudo cp -r adw-gtk3 /usr/share/themes/
    end
    
    if gum confirm "Install icon themes?"
        run_cmd git clone https://github.com/vinceliuice/Tela-icon-theme
        run_cmd sudo cp -r Tela-icon-theme /usr/share/icons/
    end
    
    run_cmd flatpak override --filesystem=$HOME/.themes
    run_cmd flatpak override --env=GTK_THEME=adw-gtk3
end

# ───📱 Applications────────────────────────────────────────────────────
function install_apps
    set choices (gum choose --no-limit \
        "Development: VS Codium,Builder" \
        "Multimedia: Blender,GIMP,Handbrake" \
        "Utilities: Transmission,Deja Dup" \
        "All Recommended Apps")
    
    contains "All Recommended Apps" $choices; and set --erase choices; set all true
    
    if $all or contains "Development" $choices
        run_cmd flatpak install -y com.vscodium.codium
        run_cmd sudo dnf install -y builder
    end
    
    if $all or contains "Multimedia" $choices
        run_cmd flatpak install -y org.blender.Blender
        run_cmd flatpak install -y org.gimp.GIMP
    end
    
    if $all or contains "Utilities" $choices
        run_cmd flatpak install -y com.transmissionbt.Transmission
        run_cmd sudo dnf install -y deja-dup
    end
end

# ───🧭 Main Menu───────────────────────────────────────────────────────
function main_menu
    check_deps || exit 1
    while true
        set choice (gum choose --header "Fedora 42 Post-Install Wizard" --height 20 \
            "🔧 Core System Setup" \
            "🖥️ Hardware Configuration" \
            "📦 Software Management" \
            "🎮 Multimedia Setup" \
            "🔒 System Tweaks" \
            "🎨 Desktop Customization" \
            "📱 Install Applications" \
            "🚪 Exit")
        
        switch $choice
            case "🔧 Core System Setup"
                enable_repos
                system_update
            case "🖥️ Hardware Configuration"
                firmware_update
                nvidia_setup
            case "📦 Software Management"
                flatpak_setup
                appimage_support
            case "🎮 Multimedia Setup"
                media_codecs
                hw_acceleration
            case "🔒 System Tweaks"
                network_config
                system_optimizations
            case "🎨 Desktop Customization"
                install_themes
            case "📱 Install Applications"
                install_apps
            case "🚪 Exit"
                echo "👋 Configuration complete! Some changes may require reboot."
                break
        end
        gum confirm "Continue with other tasks?" --default=true || break
    end
end

# ───🚀 Launch───────────────────────────────────────────────────────────
main_menu
