#!/usr/bin/env bash

# ── Colors ─────────────────────────────────────────────
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)
BOLD=$(tput bold)
DIM=$(tput dim)
RESET=$(tput sgr0)

# ── Symbols ────────────────────────────────────────────
CHECK="✔"
CROSS="✖"
INFO="ℹ"
WARNING="⚠"
ARROW="➜"
BULLET="•"

# ── Layout helpers ─────────────────────────────────────
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
CONTENT_WIDTH=$((TERM_WIDTH - 4))

line() {
    printf "%*s" "$CONTENT_WIDTH" | tr ' ' '─'
}

center() {
    local text="$1"
    printf "%*s" $(((${#text} + CONTENT_WIDTH) / 2)) "$text"
}

print_header() {
    echo
    echo -e "${CYAN}┌$(line)┐${RESET}"
    printf "${CYAN}│${RESET}%s${CYAN}│${RESET}\n" "$(center "${BOLD}$1${RESET}")"
    echo -e "${CYAN}└$(line)┘${RESET}"
}

print_section() {
    echo
    echo -e "${MAGENTA}${BULLET} ${WHITE}$1${RESET}"
    echo -e "${DIM}$(line)${RESET}"
}

print_kv() {
    local key="$1"
    local value="$2"
    printf "  ${CYAN}%-16s${RESET} ${WHITE}%s${RESET}\n" "$key:" "$value"
}

print_divider() {
    echo -e "${DIM}$(line)${RESET}"
}

show_progress() {
    echo -ne "${CYAN}${ARROW}${RESET} $1..."
}

show_done() {
    echo -e " ${GREEN}${CHECK}${RESET}"
}

# ── Helpers ────────────────────────────────────────────
compare_time() {
    local t="$1"
    local threshold="$2"

    t=$(echo "$t" | sed 's/[^0-9.]//g')

    if echo "$t > $threshold" | bc -l 2>/dev/null | grep -q 1; then
        echo 1
    else
        echo 0
    fi
}

# ── Boot Time ──────────────────────────────────────────
analyze_boot_time() {
    print_section "System Boot Overview"

    show_progress "Analyzing boot time"
    local output
    output=$(systemd-analyze time 2>/dev/null)
    show_done

    if [ -z "$output" ]; then
        echo -e "${DIM}No boot data available${RESET}"
        return
    fi

    print_divider

    print_kv "Firmware" "$(echo "$output" | grep -oP '[0-9.]+s \(firmware\)')"
    print_kv "Loader"   "$(echo "$output" | grep -oP '[0-9.]+s \(loader\)')"
    print_kv "Kernel"   "$(echo "$output" | grep -oP '[0-9.]+(ms|s) \(kernel\)')"
    print_kv "Initrd"   "$(echo "$output" | grep -oP '[0-9.]+s \(initrd\)')"
    print_kv "Userspace" "$(echo "$output" | grep -oP '[0-9.]+s \(userspace\)')"

    print_divider

    total=$(echo "$output" | grep -oP '= .*' | sed 's/= //')
    print_kv "Total Boot" "$total"
}

# ── Critical Chain ─────────────────────────────────────
analyze_critical_chain() {
    print_section "Critical Boot Path"

    show_progress "Analyzing critical chain"
    local output
    output=$(systemd-analyze critical-chain --no-pager 2>/dev/null)
    show_done

    if [ -z "$output" ]; then
        echo -e "${DIM}No critical chain data${RESET}"
        return
    fi

    print_divider

    echo "$output" | while read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == *"The time"* ]] && continue

        echo -e "  ${WHITE}$line${RESET}"
    done
}

# ── Slow Services ──────────────────────────────────────
analyze_service_blame() {
    print_section "Slowest Services"

    show_progress "Analyzing services"
    local file
    file=$(mktemp)
    systemd-analyze blame --no-pager > "$file" 2>/dev/null
    show_done

    if [ ! -s "$file" ]; then
        echo -e "${DIM}No service data${RESET}"
        rm -f "$file"
        return
    fi

    print_divider

    local count=1
    while read -r line; do
        [[ -z "$line" ]] && continue
        [ $count -gt 15 ] && break

        time=$(awk '{print $1}' <<< "$line")
        service=$(awk '{$1=""; print $0}' <<< "$line" | xargs)

        service=$(printf "%b" "$service")

        # color logic
        color="$GREEN"
        icon="$CHECK"

        if [ "$(compare_time "$time" 30)" -eq 1 ]; then
            color="$RED"; icon="$WARNING"
        elif [ "$(compare_time "$time" 5)" -eq 1 ]; then
            color="$YELLOW"; icon="$INFO"
        elif [ "$(compare_time "$time" 1)" -eq 1 ]; then
            color="$CYAN"
        fi

        printf "  ${DIM}%2d.${RESET} ${color}%7s${RESET}  ${icon}  ${WHITE}%-50s${RESET}\n" \
            "$count" "$time" "$service"

        ((count++))
    done < "$file"

    rm -f "$file"
}

# ── System Info ────────────────────────────────────────
system_info() {
    print_section "System Information"

    version=$(systemctl --version | head -n1)

    state=$(systemctl is-system-running 2>/dev/null)

    print_kv "Kernel" "$(uname -r)"
    print_kv "Arch" "$(uname -m)"
    print_kv "Systemd" "$version"
    print_kv "State" "$state"
}

# ── Main ──────────────────────────────────────────────
run_analysis() {
    print_header "Systemd Boot Analysis"

    if ! command -v systemd-analyze >/dev/null; then
        echo -e "${RED}${CROSS} systemd-analyze not found${RESET}"
        exit 1
    fi

    analyze_boot_time
    analyze_critical_chain
    analyze_service_blame
    system_info

    echo
    echo -e "${GREEN}$(line)${RESET}"
    echo -e "   ${WHITE}Analysis Complete ${GREEN}${CHECK}${RESET}"
    echo -e "${GREEN}$(line)${RESET}"
    echo
}

run_analysis
