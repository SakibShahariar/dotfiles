#!/usr/bin/env bash

# Force UTF-8 encoding
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

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
    local width="${1:-$CONTENT_WIDTH}"
    printf '─%.0s' $(seq 1 "$width")
}

center() {
    local text="$1"
    # Strip ANSI/tput escape sequences to get visible length
    local visible
    visible=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local textlen=${#visible}
    local pad=$(( (CONTENT_WIDTH - textlen) / 2 ))
    printf "%${pad}s%s%${pad}s" "" "$text" ""
}

print_header() {
    local title="${BOLD}$1${RESET}"
    echo
    echo -e "${CYAN}┌$(line)┐${RESET}"
    printf "${CYAN}│${RESET} %s ${CYAN}│${RESET}\n" "$(center "$title")"
    echo -e "${CYAN}└$(line)┘${RESET}"
}

print_section() {
    echo
    echo -e "${MAGENTA}${BULLET} ${WHITE}${BOLD}$1${RESET}"
    echo -e "${DIM}$(line)${RESET}"
}

print_kv() {
    local key="$1"
    local value="$2"
    printf "  ${CYAN}%-16s${RESET} ${WHITE}%s${RESET}\n" "$key:" "$value"
}

print_kv_percent() {
    local key="$1"
    local value="$2"
    local percent="$3"

    # Determine color — check highest threshold first, don't overwrite
    local color="$GREEN"
    if [ "$(echo "$percent > 25" | bc -l 2>/dev/null)" = "1" ]; then
        color="$RED"
    elif [ "$(echo "$percent > 15" | bc -l 2>/dev/null)" = "1" ]; then
        color="$YELLOW"
    fi

    printf "  ${CYAN}%-16s${RESET} ${color}%8s${RESET} ${DIM}(%5.1f%%)${RESET}\n" "$key:" "$value" "$percent"
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
    if [ "$(echo "$t > $threshold" | bc -l 2>/dev/null)" = "1" ]; then
        echo 1
    else
        echo 0
    fi
}

extract_time() {
    local str="$1"
    echo "$str" | sed 's/[^0-9.]//g'
}

decode_device_name() {
    local name="$1"
    # Handle both \x2d (critical-chain) and bare x2d (blame) encodings
    # Use sed to match both forms in one pass: optional backslash before xNN
    name=$(echo "$name" | sed '
        s/\\x2d/-/g
        s/\\x2e/./g
        s/\\x2b/+/g
        s/\\x2f/\//g
        s/\\x40/@/g
        s/\\x3a/:/g
        s/x2d/-/g
        s/x2e/./g
        s/x2b/+/g
        s/x2f/\//g
        s/x40/@/g
        s/x3a/:/g
    ')
    echo "$name"
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

    local total_str
    total_str=$(echo "$output" | grep -oP '= .*' | sed 's/= //')

    # Parse each phase directly from the raw output line
    # Format: Startup finished in Xs (firmware) + Xs (loader) + Xs (kernel) + Xs (initrd) + Xs (userspace) = Xs
    local firmware loader initrd userspace
    firmware=$(echo "$output" | grep -oP '[0-9.]+(?=s \(firmware\))')
    loader=$(echo "$output"   | grep -oP '[0-9.]+(?=s \(loader\))')
    initrd=$(echo "$output"   | grep -oP '[0-9.]+(?=s \(initrd\))')
    userspace=$(echo "$output" | grep -oP '[0-9.]+(?=s \(userspace\))')

    # Kernel may be in ms or s
    local kernel_line kernel_raw kernel
    kernel_line=$(echo "$output" | grep -oP '[0-9.]+m?s \(kernel\)')
    kernel_raw=$(echo "$kernel_line" | grep -oP '^[0-9.]+')
    if echo "$kernel_line" | grep -q 'ms'; then
        kernel=$(echo "scale=3; $kernel_raw / 1000" | bc -l 2>/dev/null)
    else
        kernel="$kernel_raw"
    fi
    # Ensure leading zero (bc gives .785 instead of 0.785)
    [[ "$kernel" == .* ]] && kernel="0${kernel}"

    # Default to 0 if missing
    firmware="${firmware:-0}"; loader="${loader:-0}"; kernel="${kernel:-0}"
    initrd="${initrd:-0}";     userspace="${userspace:-0}"

    # Sum all phases to get total_sec (more reliable than parsing the "= Xs" total)
    local total_sec
    total_sec=$(echo "scale=3; $firmware + $loader + $kernel + $initrd + $userspace" | bc -l 2>/dev/null)
    # Fallback: parse from total_str
    if [ -z "$total_sec" ] || [ "$total_sec" = "0" ]; then
        total_sec=$(echo "$total_str" | grep -oP '[0-9]+\.[0-9]+' | head -1)
    fi

    # Calculate percentages inline (avoids nested function/local scoping issues)
    # Multiply by 100 FIRST before dividing — bc truncates at scale=1 mid-expression
    # e.g. (2.034 / 20.575) * 100 = 0.0 * 100 = 0  ← WRONG
    #       2.034 * 100 / 20.575  = 203.4 / 20.575  ← CORRECT
    local fw_pct ld_pct kr_pct ir_pct us_pct
    fw_pct=$(echo "scale=1; $firmware  * 100 / $total_sec" | bc -l 2>/dev/null || echo "0")
    ld_pct=$(echo "scale=1; $loader    * 100 / $total_sec" | bc -l 2>/dev/null || echo "0")
    kr_pct=$(echo "scale=1; $kernel    * 100 / $total_sec" | bc -l 2>/dev/null || echo "0")
    ir_pct=$(echo "scale=1; $initrd    * 100 / $total_sec" | bc -l 2>/dev/null || echo "0")
    us_pct=$(echo "scale=1; $userspace * 100 / $total_sec" | bc -l 2>/dev/null || echo "0")

    print_kv_percent "Firmware"  "${firmware}s"  "$fw_pct"
    print_kv_percent "Loader"    "${loader}s"    "$ld_pct"
    print_kv_percent "Kernel"    "${kernel}s"    "$kr_pct"
    print_kv_percent "Initrd"    "${initrd}s"    "$ir_pct"
    print_kv_percent "Userspace" "${userspace}s" "$us_pct"

    print_divider
    print_kv "Total Boot" "$total_str"
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

    # ── Parse all entries into arrays ──────────────────
    local -a names starts delays raw_lines
    local total_start=0

    while IFS= read -r ln; do
        [[ -z "$ln" ]] && continue
        [[ "$ln" == *"The time"* ]] && continue
        [[ "$ln" == *"Requires"* ]] && continue
        [[ "$ln" == *"After"* ]] && continue

        # Extract @X.Xs start time
        local start=0
        if [[ "$ln" =~ @([0-9]+\.[0-9]+)s ]]; then
            start="${BASH_REMATCH[1]}"
        fi

        # Extract +Xms or +Xs activation delay
        local delay=0
        if [[ "$ln" =~ \+([0-9]+)ms ]]; then
            delay=$(echo "scale=3; ${BASH_REMATCH[1]} / 1000" | bc -l 2>/dev/null)
        elif [[ "$ln" =~ \+([0-9]+\.[0-9]+)s ]]; then
            delay="${BASH_REMATCH[1]}"
        fi

        names+=("$ln")
        starts+=("$start")
        delays+=("$delay")

        # Track max start time for bar scaling
        if (( $(echo "$start > $total_start" | bc -l 2>/dev/null) )); then
            total_start="$start"
        fi
    done <<< "$output"

    local count=${#names[@]}
    if [ "$count" -eq 0 ]; then
        echo -e "${DIM}No chain entries found${RESET}"
        return
    fi

    # ── Find slowest single activation delay ──────────
    local max_delay=0 max_idx=0
    for i in "${!delays[@]}"; do
        local d="${delays[$i]}"
        if (( $(echo "$d > $max_delay" | bc -l 2>/dev/null) )); then
            max_delay="$d"
            max_idx=$i
        fi
    done

    # ── Depth trimming: show first 6, last 1, collapse middle ──
    local MAX_SHOW=8
    local show_collapse=0
    local collapse_from=0 collapse_to=0
    if [ "$count" -gt "$MAX_SHOW" ]; then
        show_collapse=1
        collapse_from=6
        collapse_to=$(( count - 2 ))
    fi

    # ── Bar width available (after indent + time labels) ──
    local BAR_WIDTH=12

    render_bar() {
        local start="$1"
        local total="$2"
        local width="$3"
        local filled=0
        if (( $(echo "$total > 0" | bc -l 2>/dev/null) )); then
            filled=$(echo "scale=0; ($start * $width / $total) / 1" | bc -l 2>/dev/null)
        fi
        [ "$filled" -gt "$width" ] && filled=$width
        local empty=$(( width - filled ))
        printf "${DIM}[${RESET}${CYAN}"
        printf '█%.0s' $(seq 1 $filled 2>/dev/null) 2>/dev/null || true
        printf "${DIM}"
        printf '░%.0s' $(seq 1 $empty 2>/dev/null) 2>/dev/null || true
        printf "]${RESET}"
    }

    delay_color() {
        local d="$1"
        if (( $(echo "$d > 1.0" | bc -l 2>/dev/null) )); then
            echo "$RED"
        elif (( $(echo "$d > 0.3" | bc -l 2>/dev/null) )); then
            echo "$YELLOW"
        else
            echo "$GREEN"
        fi
    }

    # ── Render ─────────────────────────────────────────
    local skipped=0
    for i in "${!names[@]}"; do
        local ln="${names[$i]}"
        local start="${starts[$i]}"
        local delay="${delays[$i]}"

        # Collapse middle entries
        if [ "$show_collapse" -eq 1 ] && [ "$i" -ge "$collapse_from" ] && [ "$i" -le "$collapse_to" ]; then
            skipped=$(( skipped + 1 ))
            continue
        fi

        # Print collapse summary before last entry
        if [ "$show_collapse" -eq 1 ] && [ "$skipped" -gt 0 ] && [ "$i" -eq $(( collapse_to + 1 )) ]; then
            echo -e "  ${DIM}     ┆ … ${skipped} intermediate steps collapsed …${RESET}"
            skipped=0
        fi

        # Strip tree chars and extract the unit name + times
        local tree_prefix name_part
        tree_prefix=$(echo "$ln" | grep -oP '^[\s└─├│ ]+' || echo "")
        name_part=$(echo "$ln" | sed 's/^[[:space:]└─├│]*//')
        # After collapsing, replace deep indent with a fixed short one
        if [ "$show_collapse" -eq 1 ] && [ "$i" -eq $(( collapse_to + 1 )) ]; then
            tree_prefix="  └─"
        fi

        # Decode hex-escaped chars in device names (x2d -> -, x2e -> . etc)
        name_part=$(decode_device_name "$name_part")

        # Unit name: strip everything from @ onward, trim trailing space
        local unit_name="${name_part%%@*}"
        unit_name="${unit_name%% }"

        # Slowest marker
        local marker="  "
        if [ "$i" -eq "$max_idx" ]; then
            marker="${YELLOW}★ ${RESET}"
        fi

        # Delay badge
        local delay_badge=""
        if (( $(echo "$delay > 0" | bc -l 2>/dev/null) )); then
            local dc
            dc=$(delay_color "$delay")
            local delay_ms
            delay_ms=$(echo "scale=0; $delay * 1000 / 1" | bc -l 2>/dev/null)
            if (( $(echo "$delay >= 1.0" | bc -l 2>/dev/null) )); then
                delay_badge=" ${dc}+${delay}s${RESET}"
            else
                delay_badge=" ${dc}+${delay_ms}ms${RESET}"
            fi
        fi

        # Timeline bar
        local bar
        bar=$(render_bar "$start" "$total_start" "$BAR_WIDTH")

        # Unit name coloring: bold for slowest
        local name_color="$WHITE"
        [ "$i" -eq "$max_idx" ] && name_color="${BOLD}${YELLOW}"

        # Time label: suppress @0s for leaf devices that have no real start time
        local time_label=""
        if [[ "$start" != "0" ]]; then
            time_label="${DIM}@${start}s${RESET}"
        fi

        printf "  %s%s %s%s %s%s${RESET}\n" \
            "$marker" \
            "$bar" \
            "${name_color}" \
            "${tree_prefix}${unit_name}" \
            "$time_label" \
            "$delay_badge"
    done

    # Legend
    echo
    printf "  ${DIM}Bar = start time  ${CYAN}█${DIM} active  ░ waiting  ${YELLOW}★${DIM} slowest activation${RESET}\n"
    printf "  ${DIM}Delay: ${GREEN}■ <300ms  ${YELLOW}■ 300ms–1s  ${RED}■ >1s${RESET}\n"
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
    while IFS= read -r ln; do
        [[ -z "$ln" ]] && continue
        [ $count -gt 15 ] && break

        local time service
        time=$(awk '{print $1}' <<< "$ln")
        service=$(awk '{$1=""; print $0}' <<< "$ln" | xargs)
        service=$(decode_device_name "$service")

        local color icon
        if [ "$(compare_time "$time" 2)" -eq 1 ]; then
            color="$RED";    icon="$WARNING"
        elif [ "$(compare_time "$time" 0.8)" -eq 1 ]; then
            color="$YELLOW"; icon="$INFO"
        elif [ "$(compare_time "$time" 0.3)" -eq 1 ]; then
            color="$CYAN";   icon="$BULLET"
        else
            color="$GREEN";  icon="$CHECK"
        fi

        printf "  ${DIM}%2d.${RESET} ${color}%7s${RESET}  %s  ${WHITE}%-50s${RESET}\n" \
            "$count" "$time" "$icon" "$service"

        ((count++))
    done < "$file"

    rm -f "$file"
}

# ── System Info ────────────────────────────────────────
system_info() {
    print_section "System Information"

    local version state
    version=$(systemctl --version | head -n1)
    state=$(systemctl is-system-running 2>/dev/null)

    print_kv "Kernel"  "$(uname -r)"
    print_kv "Arch"    "$(uname -m)"
    print_kv "Systemd" "$version"
    print_kv "State"   "$state"
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
    printf "   ${WHITE}Analysis Complete ${GREEN}${CHECK}${RESET}\n"
    echo -e "${GREEN}$(line)${RESET}"
    echo
}

run_analysis
