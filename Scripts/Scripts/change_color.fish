#!/usr/bin/env fish

set color_file "$HOME/.cache/hellwal/gtk-colors.css"
set gtk_target_file "$HOME/.config/gtk-4.0/colors.css"
set kitty_conf "$HOME/.config/kitty/colors.conf"

# Check files exist
for f in $color_file $gtk_target_file $kitty_conf
    if not test -f $f
        echo "🚫 Error: Cannot find file $f"
        exit 1
    end
end

# Grab colors from the source color file
set raw_lines (grep -- '--color' $color_file)

set color_list
for line in $raw_lines
    if string match -rq '^ *--color[0-9]+: #[0-9a-fA-F]{6};' -- $line
        set trimmed (string trim $line)
        set color_list $color_list $trimmed
    end
end

if test (count $color_list) -eq 0
    echo "🤷 No colors found in $color_file"
    exit 1
end

# Show color choices with preview block, aligned nicely
echo "🎨 Pick a color:"
set i 0
for color in $color_list
    set parts (string split ": " -- $color)
    set name $parts[1]
    set hex (string trim -c ';' $parts[2])

    set r (math "0x"(string sub -s 2 -l 2 $hex))
    set g (math "0x"(string sub -s 4 -l 2 $hex))
    set b (math "0x"(string sub -s 6 -l 2 $hex))

    printf "[%2d] %-8s %7s  \e[48;2;%d;%d;%dm  \e[0m\n" $i $name $hex $r $g $b
    set i (math $i + 1)
end

read -P "👉 Your color number (0-15): " choice

# Validate input
if not string match -qr '^[0-9]+$' -- $choice
    echo "❌ Not a number, chief."
    exit 1
end

if test $choice -lt 0 -o $choice -ge (count $color_list)
    echo "❌ That number’s out of range. Stay within the palette!"
    exit 1
end

# Access fish array with +1 offset
set selected (string split ": " -- $color_list[(math $choice + 1)])
set selected_name $selected[1]
set selected_hex (string trim -c ';' $selected[2])

echo "🌟 You picked $selected_name → $selected_hex"

# Function: Replace color var line in a file (for GTK)
function replace_color_in_file --argument-names file color_var new_hex
    sed -E -i "s/(--$color_var:\s*)#[0-9a-fA-F]{6};/\1$new_hex;/g" $file
    echo "✅ Replaced --$color_var with $new_hex in $file"
end

# Function: Replace kitty background color only
function replace_kitty_bg_color --argument-names file new_hex
    sed -E -i "s/^(background\s+)(#[0-9a-fA-F]{6})/\1$new_hex/" $file
    echo "✅ Updated background color to $new_hex in $file"
end

# Replace --color0 in GTK config ALWAYS
replace_color_in_file $gtk_target_file "color0" $selected_hex

# Replace kitty background
replace_kitty_bg_color $kitty_conf $selected_hex

# Refresh kitty config (reload colors)
kitty @ set-colors --all --config $kitty_conf 2>/dev/null; or echo "⚠️ Kitty refresh failed, maybe kitty remote is not enabled."
