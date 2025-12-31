#!/usr/bin/env fish
#
# A TUI for DNF using gum and fzf.
#
# --- Configuration ---
# Use global scope for these vars so they are accessible in functions
set CACHE_DIR "$HOME/.cache/dnf-tui"
set CACHE_FILE "$CACHE_DIR/available_packages.txt"
set CACHE_TTL (math 60 \* 60 \* 6) # 6 hours in seconds

# --- Helper Functions ---

# Check for required dependencies
function check_dependencies
    set -l missing_deps
    for dep in gum fzf
        if not command -v $dep >/dev/null
            set -a missing_deps $dep
        end
    end
    
    # repoquery might be from dnf-plugins-core
    if not command -v repoquery >/dev/null
        if not command -v dnf >/dev/null
            set -a missing_deps "dnf (and dnf-plugins-core)"
        else
            set -a missing_deps "dnf-plugins-core (for repoquery)"
        end
    end
    
    if test (count $missing_deps) -gt 0
        gum style --foreground "red" --bold "Error: Missing dependencies:"
        echo
        for dep in $missing_deps
            gum style --foreground "red" "  - $dep"
        end
        echo
        return 1
    end
    return 0
end

# Get list of available packages, using a cache to improve performance
function get_available_packages
    mkdir -p $CACHE_DIR
    
    set -l cache_age 0
    if test -f $CACHE_FILE
        set cache_age (math (date +%s) - (stat -c %Y $CACHE_FILE 2>/dev/null || echo 0))
    end
    
    set -l cache_is_stale false
    if test $cache_age -eq 0; or test $cache_age -gt $CACHE_TTL
        set cache_is_stale true
    end
    
    if $cache_is_stale
        gum style --foreground "blue" "The package cache is stale (older than "(math $CACHE_TTL / 3600)" hours)."
        echo
        if not gum confirm "Do you want to refresh the cache now? This might take a moment."
            gum style --foreground "yellow" "Using stale cache. Some packages might be outdated."
            echo
            if test -f $CACHE_FILE
                cat $CACHE_FILE
            end
            return 0
        end
        echo
        gum style --foreground "blue" "Refreshing package cache. This might take a moment..."
        # Fetch list and save to cache
        if not gum spin --spinner dot --title "Refreshing package cache..." -- \
                repoquery --available --quiet --queryformat '%{name}' | sort -u >$CACHE_FILE
            gum style --foreground "red" --bold "Error: Failed to fetch available packages."
            echo
            return 1
        end
        echo
    end
    cat $CACHE_FILE
end

# Get list of user-installed packages
function get_installed_packages
    if not gum spin --spinner dot --title "Fetching installed packages..." -- \
            repoquery --userinstalled --quiet --queryformat '%{name}' | sort -u
        gum style --foreground "red" --bold "Error: Failed to fetch installed packages."
        echo
        return 1
    end
end

# Use fzf to pick from a list of packages
function pick_packages -a prompt_text -a package_cmd
    set -l temp_list (mktemp)
    
    if not $package_cmd >$temp_list
        rm -f $temp_list
        return 1
    end
    
    # Check if list is empty
    if not test -s $temp_list
        gum style --foreground "yellow" --bold "Warning: No packages found for this operation."
        echo
        rm -f $temp_list
        return 1
    end
    
    fzf --multi --prompt="$prompt_text" --preview 'dnf -C info {}' <$temp_list
    set -l result_code $status
    rm -f $temp_list
    return $result_code
end

# --- Main Logic ---

if not check_dependencies
    exit 1
end

while true
    clear
    gum style \
        --foreground 212 --border-foreground 212 --border double \
        --align center --width 50 --margin "1 2" --padding "1 2" \
        'DNF Package Manager' 'Interactive TUI'
    
    echo
    
    set -l mode (gum choose \
        --header "Select an action:" \
        --cursor.foreground 212 \
        --selected.foreground 212 \
        "📦 Install" "🗑️  Remove" "🔍 Search" "ℹ️  Info" "⬆️  Update" "❌ Exit")
    
    # Exit if user cancels the menu
    test -z "$mode"; and break
    
    echo
    
    switch $mode
        case "❌ Exit"
            gum style --foreground 212 "👋 Goodbye!"
            break
            
        case "📦 Install"
            clear
            gum style --foreground 212 --bold "📦 Install Packages"
            echo
            gum style --faint "Tip: In fzf, use Tab to select multiple packages, Ctrl-C to cancel"
            echo
            
            set -l pkgs (pick_packages "Install> " get_available_packages)
            if test $status -ne 0; or test -z "$pkgs"
                continue
            end
            
            echo
            gum style --foreground 212 --bold "Selected packages:"
            for pkg in $pkgs
                gum style --foreground 255 "  • $pkg"
            end
            echo
            
            if gum confirm --affirmative "Install" --negative "Cancel" "Proceed with installation?"
                echo
                if sudo dnf install $pkgs
                    echo
                    gum style --foreground 120 --bold "✓ Installation completed successfully"
                else
                    echo
                    gum style --foreground 196 --bold "✗ Installation failed"
                end
                echo
                gum input --placeholder "Press Enter to continue..." --width 0
            end
            
        case "🗑️  Remove"
            clear
            gum style --foreground 196 --bold "🗑️  Remove Packages"
            echo
            gum style --faint "Tip: In fzf, use Tab to select multiple packages, Ctrl-C to cancel"
            echo
            
            set -l pkgs (pick_packages "Remove> " get_installed_packages)
            if test $status -ne 0; or test -z "$pkgs"
                continue
            end
            
            echo
            gum style --foreground 196 --bold "Selected packages:"
            for pkg in $pkgs
                gum style --foreground 255 "  • $pkg"
            end
            echo
            
            if gum confirm --affirmative "Remove" --negative "Cancel" "Proceed with removal?"
                echo
                if sudo dnf remove $pkgs
                    echo
                    gum style --foreground 120 --bold "✓ Removal completed successfully"
                else
                    echo
                    gum style --foreground 196 --bold "✗ Removal failed"
                end
                echo
                gum input --placeholder "Press Enter to continue..." --width 0
            end
            
        case "🔍 Search"
            clear
            gum style --foreground 81 --bold "🔍 Search Packages"
            echo
            gum style --faint "Tip: In fzf, use Tab to select multiple packages, Ctrl-C to cancel"
            echo
            # Allows searching without any action. After fzf closes, loop continues.
            pick_packages "Search> " get_available_packages >/dev/null
            
        case "ℹ️  Info"
            clear
            gum style --foreground 226 --bold "ℹ️  Package Information"
            echo
            gum style --faint "Tip: Select a package to view detailed information (dependencies, files, etc.)"
            echo
            
            set -l pkg (pick_packages "Package Info> " get_installed_packages | head -n1)
            if test -n "$pkg"
                clear
                gum style \
                    --foreground 226 --border-foreground 226 --border rounded \
                    --align center --width 60 --margin "1 2" --padding "1 2" \
                    "Package: $pkg"
                echo
                dnf info $pkg
                echo
                gum style --foreground 226 --bold "Dependencies:"
                dnf repoquery --requires $pkg
                echo
                
                if gum confirm --affirmative "Show" --negative "Skip" "Show installed files?"
                    clear
                    gum style --foreground 226 --bold "Installed Files: $pkg"
                    echo
                    rpm -ql $pkg | less
                end
                echo
                gum input --placeholder "Press Enter to continue..." --width 0
            end
            
        case "⬆️  Update"
            clear
            gum style --foreground 51 --bold "⬆️  Update System"
            echo
            
            if gum confirm --affirmative "Update" --negative "Cancel" "Update all packages?"
                echo
                if sudo dnf upgrade
                    echo
                    gum style --foreground 120 --bold "✓ Update completed successfully"
                else
                    echo
                    gum style --foreground 196 --bold "✗ Update failed"
                end
                echo
                gum input --placeholder "Press Enter to continue..." --width 0
            end
    end
end
