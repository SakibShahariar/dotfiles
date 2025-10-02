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
    for dep in gum fzf repoquery
        if not command -v $dep >/dev/null
            set -a missing_deps $dep
        end
    end

    if test (count $missing_deps) -gt 0
        gum style --foreground "197" "Error: Missing dependencies: "(string join ", " $missing_deps)
        gum style "Please install them to use this script."
        return 1
    end
    return 0
end

# Get list of available packages, using a cache to improve performance
function get_available_packages
    mkdir -p $CACHE_DIR
    set -l cache_is_stale false
    if not test -f $CACHE_FILE; or test (math (date +%s) - (date -r $CACHE_FILE +%s)) -gt $CACHE_TTL
        set cache_is_stale true
    end

    if $cache_is_stale
        # Fetch list and save to cache
        if not gum spin --spinner dot --title "Refreshing package cache..." -- \
                repoquery --available --quiet --queryformat '%{name}' | sort -u >$CACHE_FILE
            gum style --foreground "197" "Error: Failed to fetch available packages."
            return 1
        end
    end
    cat $CACHE_FILE
end

# Get list of user-installed packages
function get_installed_packages
    if not gum spin --spinner dot --title "Fetching installed packages..." -- \
            repoquery --userinstalled --quiet --queryformat '%{name}' | sort -u
        gum style --foreground "197" "Error: Failed to fetch installed packages."
        return 1
    end
end

# Use fzf to pick from a list of packages
function pick_packages -a prompt_text -a package_cmd
    set -l temp_list (mktemp)
    trap "rm -f $temp_list" EXIT # Ensure cleanup

    if not $package_cmd >$temp_list
        return 1 # Error occurred in package command
    end

    # Check if list is empty
    if not test -s $temp_list
        gum style --foreground "220" "Warning: No packages found for this operation."
        return 1
    end

    fzf --multi --prompt="$prompt_text" --preview 'dnf -C info {}' <$temp_list
end


# --- Main Logic ---

if not check_dependencies
    exit 1
end

while true
    set -l mode (gum choose "Install" "Remove" "Search" "Exit")
    # Exit if user cancels the menu
    test -z "$mode"; and break

    switch $mode
        case "Exit"
            break

        case "Install"
            set -l pkgs (pick_packages "Install> " get_available_packages)
            if test -z "$pkgs"
                # User cancelled, go back to menu
                continue
            end
            if gum confirm "Install the following packages?\n\n"(string join "\n" $pkgs)
                sudo dnf install $pkgs
            end

        case "Remove"
            set -l pkgs (pick_packages "Remove> " get_installed_packages)
            if test -z "$pkgs"
                # User cancelled, go back to menu
                continue
            end
            if gum confirm "Remove the following packages?\n\n"(string join "\n" $pkgs)
                sudo dnf remove $pkgs
            end

        case "Search"
            # Allows searching without any action. After fzf closes, loop continues.
            pick_packages "Search> " get_available_packages >/dev/null
    end
end
