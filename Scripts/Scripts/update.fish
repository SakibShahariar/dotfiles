#!/usr/bin/env fish

# Define color scheme
set color_header (set_color -o white)
set color_update (set_color -o cyan)
set color_success (set_color -o green)
set color_warning (set_color -o yellow)
set color_reset (set_color normal)

# System info
set os_info (grep '^PRETTY_NAME=' /etc/os-release | cut -d '"' -f2)
set kernel_info (uname -r)
set uptime_info (uptime -p | string replace -r '^up ' '')

# Function to display aligned system info
function show_system_info
    echo -e "\n$color_header🚀 System Status$color_reset"
    echo -e "$color_update----------------------------------------$color_reset"
    printf "  %-12s %s\n" "OS:" "$os_info"
    printf "  %-12s %s\n" "Kernel:" "$kernel_info"
    printf "  %-12s %s\n" "Uptime:" "$uptime_info"
    echo -e "$color_update----------------------------------------$color_reset\n"
end

# Main execution
show_system_info

# Update process
echo -e "$color_header▶ Starting System Updates$color_reset\n"

# Update system packages with refreshed metadata
echo -e "\n$color_update🔄 System Packages Update$color_reset"

sudo dnf update --refresh -y

# Update Flatpaks
echo -e "\n$color_update📦 Flatpak Applications Update$color_reset"
flatpak update -y

# Remove unused Flatpaks
echo -e "\n$color_update🧯 Cleaning Up Unused Flatpaks$color_reset"
flatpak uninstall --unused -y

# Firmware update
# echo -e "\n$color_update🔧 Firmware Updates Check$color_reset"
# sudo fwupdmgr update

# Show what packages were updated
echo -e "$color_update🔄 Packages Updated$color_reset"
dnf history info last | grep -E 'Updated|Name'

# All done
echo -e "\n$color_success✅ System updates completed successfully!$color_reset"

notify-send -i system-software-update "✅ Updates Done" "System is up to date!"
