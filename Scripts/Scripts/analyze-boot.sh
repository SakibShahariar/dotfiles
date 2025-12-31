#!/usr/bin/env bash

# Enhanced color setup
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
CYAN=$(tput setaf 6)
YELLOW=$(tput setaf 3)
MAGENTA=$(tput setaf 5)
BLUE=$(tput setaf 4)
WHITE=$(tput setaf 7)
BRIGHT_WHITE=$(tput bold; tput setaf 7)
DIM=$(tput dim)
RESET=$(tput sgr0)

# Add symbols
CHECK="✅"
CROSS="❌"
INFO="ℹ️"
WARNING="⚠️"
ARROW="➜"
BULLET="•"
DIVIDER="─"

# Progress indicator
show_progress() {
    echo -ne "\r${CYAN}${ARROW}${RESET} $1..."
}

show_done() {
    echo -ne "\r${GREEN}${CHECK}${RESET}"
}

# Enhanced header function
print_header() {
    local title="$1"
    local title_length=${#title}
    local width=60
    local padding_left=$(( (width - title_length - 2) / 2 ))
    local padding_right=$(( width - padding_left - title_length - 2 ))
    
    local left_pad=$(printf '%*s' $padding_left | tr ' ' '═')
    local right_pad=$(printf '%*s' $padding_right | tr ' ' '═')
    
    echo -e "\n${CYAN}╔${left_pad} ${WHITE}${title} ${CYAN}${right_pad}╗${RESET}"
}

print_footer() {
    echo -e "${CYAN}╚$(printf '%*s' 60 | tr ' ' '═')╝${RESET}\n"
}

print_section() {
    echo -e "\n${MAGENTA}${BULLET} $1${RESET}"
    echo -e "${DIM}$(printf '%*s' 40 | tr ' ' "${DIVIDER}")${RESET}"
}

print_info() {
    echo -e "${CYAN}${INFO}${RESET} $1"
}

print_success() {
    echo -e "${GREEN}${CHECK}${RESET} $1"
}

print_warning() {
    echo -e "${YELLOW}${WARNING}${RESET} $1"
}

# Helper function for numeric comparisons
compare_time() {
    local time="$1"
    local threshold="$2"
    local clean_time
    
    # Remove non-numeric characters
    clean_time=$(echo "$time" | sed 's/[^0-9.]//g')
    
    # Convert minutes to seconds if needed
    if echo "$time" | grep -q "min"; then
        local minutes=$(echo "$time" | sed 's/[^0-9.]//g')
        clean_time=$(echo "$minutes * 60" | bc 2>/dev/null || echo 120)
    fi
    
    # Compare using bc
    if echo "$clean_time > $threshold" | bc -l 2>/dev/null | grep -q 1; then
        echo 1
    else
        echo 0
    fi
}

# Enhanced analysis functions
analyze_boot_time() {
    print_section "System Boot Overview"
    
    show_progress "Analyzing boot time"
    local output
    output=$(sudo systemd-analyze time 2>/dev/null || echo "")
    show_done
    echo
    
    echo -e "${WHITE}Boot Results:${RESET}"
    echo -e "${DIM}$(printf '%*s' 40 | tr ' ' "${DIVIDER}")${RESET}"
    
    if [ -n "$output" ]; then
        # Colorize the boot time output
        output=$(echo "$output" | sed -E "s/([0-9.]+(ms|s))/${CYAN}\1${RESET}/g")
        output=$(echo "$output" | sed -E "s/(firmware|loader|kernel|initrd|userspace)/${YELLOW}\1${RESET}/g")
        output=$(echo "$output" | sed -E "s/(graphical\.target)/${GREEN}\1${RESET}/g")
        output=$(echo "$output" | sed -E "s/(=)/${BRIGHT_WHITE}\1${RESET}/g")
        
        echo -e "${BULLET} $output"
    else
        echo -e "${DIM}Could not retrieve boot time data${RESET}"
    fi
}

analyze_critical_chain() {
    print_section "Critical Boot Path"
    
    show_progress "Analyzing critical chain"
    local output
    output=$(sudo systemd-analyze critical-chain --no-pager 2>&1 || echo "")
    show_done
    echo
    
    echo -e "${WHITE}Critical Chain Analysis:${RESET}"
    echo -e "${DIM}(The time after '@' is when the unit became active)"
    echo -e "${DIM}(The time after '+' is how long it took to start)${RESET}"
    echo -e "${DIM}$(printf '%*s' 40 | tr ' ' "${DIVIDER}")${RESET}"
    
    # Check if we got any meaningful output
    if [ -z "$output" ] || echo "$output" | grep -q "No critical chain"; then
        echo -e "${YELLOW}Note: No critical chain data available${RESET}"
        echo -e "${DIM}Try running with full root privileges or system may be fully idle.${RESET}"
        return
    fi
    
    # Remove any grep warnings
    output=$(echo "$output" | grep -v "grep: warning" 2>/dev/null || echo "$output")
    
    # Process output line by line
    echo "$output" | while IFS= read -r line; do
        # Skip empty lines
        if [ -z "$line" ]; then
            continue
        fi
        
        # Skip the explanation lines (we already printed our own)
        if echo "$line" | grep -q "The time when unit"; then
            continue
        fi
        
        echo "$line"
    done
}

analyze_service_blame() {
    print_section "Slowest Services"
    
    show_progress "Analyzing service performance"
    
    # Get service blame output
    local tempfile
    tempfile=$(mktemp)
    systemd-analyze blame --no-pager 2>/dev/null > "$tempfile" || true
    
    show_done
    echo
    
    echo -e "${WHITE}Top 15 Slowest Services:${RESET}"
    echo -e "${DIM}$(printf '%*s' 40 | tr ' ' "${DIVIDER}")${RESET}"
    
    # Check if we got output
    if [ ! -s "$tempfile" ]; then
        echo -e "${DIM}No service data available.${RESET}"
        rm -f "$tempfile"
        return
    fi
    
    # Process the file line by line
    local count=1
    while IFS= read -r line; do
        # Skip empty lines
        if [ -z "$line" ]; then
            continue
        fi
        
        # Stop after 15 lines
        if [ $count -gt 15 ]; then
            break
        fi
        
        # Extract time (first word) and service (rest)
        local time=$(echo "$line" | awk '{print $1}')
        local service=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
        
        if [ -z "$service" ]; then
            service="Unknown"
        fi
        
        # Format time with color
        local time_seconds=$(echo "$time" | sed 's/[^0-9.]//g')
        local time_display="$time"
        
        # Check if it's in minutes format
        if echo "$time" | grep -q "min"; then
            local minutes=$(echo "$time" | sed 's/[^0-9.]//g')
            time_seconds=$(echo "$minutes * 60" | bc 2>/dev/null || echo 120)
        fi
        
        # Determine color and icon based on time
        local color_time="$CYAN"
        local icon="$CHECK"
        
        if [ "$(compare_time "$time_seconds" 30)" -eq 1 ]; then
            color_time="$RED"
            icon="$WARNING"
        elif [ "$(compare_time "$time_seconds" 5)" -eq 1 ]; then
            color_time="$YELLOW"
            icon="$INFO"
        elif [ "$(compare_time "$time_seconds" 1)" -eq 1 ]; then
            color_time="$CYAN"
            icon="$CHECK"
        else
            color_time="$GREEN"
            icon="$CHECK"
        fi
        
        # Clean up service name (remove duplicate "dev-" prefix)
        service=$(echo "$service" | sed 's/^dev-dev-/dev-/')
        
        # Convert hex escapes to hyphens
        service=$(echo "$service" | sed 's/\\x2d/-/g')
        
        # Truncate very long service names
        if [ ${#service} -gt 45 ]; then
            service="${service:0:42}..."
        fi
        
        # Format output with numbering
        printf "  %2d. ${color_time}%8s${RESET} ${icon} ${WHITE}%s${RESET}\n" "$count" "$time_display" "$service"
        
        count=$((count + 1))
    done < "$tempfile"
    
    # Clean up
    rm -f "$tempfile"
}

# Main analysis function
run_analysis() {
    print_header "Systemd Boot Analysis"
    
    # Check systemd availability
    if ! command -v systemd-analyze >/dev/null 2>&1; then
        echo -e "${CROSS}${RED} Error: systemd-analyze not found!${RESET}"
        echo -e "${DIM} This script requires systemd to be installed and running.${RESET}"
        exit 1
    fi
    
    # Run analyses
    analyze_boot_time
    analyze_critical_chain
    analyze_service_blame
    
    # Additional system info
    print_section "System Information"
    echo -e "${BULLET}${CYAN} System:${RESET} ${WHITE}$(uname -srm)${RESET}"
    
    # Safely get systemd version
    local systemd_version
    systemd_version=$(sudo systemctl --version 2>/dev/null | head -n1 | xargs || echo "")
    if [ -n "$systemd_version" ]; then
        echo -e "${BULLET}${CYAN} Init System:${RESET} ${WHITE}${systemd_version}${RESET}"
    else
        echo -e "${BULLET}${CYAN} Init System:${RESET} ${WHITE}Unknown${RESET}"
    fi
    
    # Safely get boot mode
    local boot_mode
    boot_mode=$(sudo systemctl is-system-running 2>/dev/null || echo "")
    if [ $? -eq 0 ] && [ -n "$boot_mode" ]; then
        echo -e "${BULLET}${CYAN} Boot Mode:${RESET} ${WHITE}${boot_mode}${RESET}"
    else
        echo -e "${BULLET}${CYAN} Boot Mode:${RESET} ${YELLOW}Could not determine${RESET}"
    fi
    
    print_footer
}

# Run with error handling
run_analysis
echo -e "${GREEN}════════════════════════════════════════════${RESET}"
echo -e "   ${WHITE} Analysis Complete! ${GREEN}${CHECK}${RESET}   "
echo -e "${GREEN}════════════════════════════════════════════${RESET}\n"
