
#!/usr/bin/fish

set -l tela_colors \
    "Tela-circle-dracula-dark 44475a" \
    "Tela-circle-nord-dark 4d576a" \
    "Tela-circle-grey-dark bdbdbd" \
    "Tela-circle-purple-dark 7e57c2" \
    "Tela-circle-brown-dark 795548" \
    "Tela-circle-red-dark ef5350" \
    "Tela-circle-manjaro-dark 16a085" \
    "Tela-circle-blue-dark 5677fc" \
    "Tela-circle-pink-dark f06292" \
    "Tela-circle-black-dark 4d4d4d" \
    "Tela-circle-ubuntu-dark fb8441" \
    "Tela-circle-green-dark 66bb6a"

function hex_to_rgb
    set -l hex (string replace -r '^#' '' -- $argv[1])
    if test (string length $hex) -eq 3
        set hex (string split '' $hex | string join '')
    end
    set -l r (math "0x"(string sub -s 1 -l 2 $hex))
    set -l g (math "0x"(string sub -s 3 -l 2 $hex))
    set -l b (math "0x"(string sub -s 5 -l 2 $hex))
    echo $r $g $b
end

function rgb_to_hsv
    set -l r (math -s4 "$argv[1] / 255.0")
    set -l g (math -s4 "$argv[2] / 255.0")
    set -l b (math -s4 "$argv[3] / 255.0")

    set -l max (math -s4 "max($r, $g, $b)")
    set -l min (math -s4 "min($r, $g, $b)")
    set -l delta (math -s4 "$max - $min")

    set -l h 0
    if test $delta -ne 0
        if test $r -eq $max
            set h (math -s4 "((($g - $b) / $delta) % 6) * 60")
        else if test $g -eq $max
            set h (math -s4 "(($b - $r) / $delta + 2) * 60")
        else
            set h (math -s4 "(($r - $g) / $delta + 4) * 60")
        end
        set h (math -s4 "($h + 360) % 360")
    end

    set -l s 0
    if test $max -ne 0
        set s (math -s4 "$delta / $max")
    end

    set -l v $max
    echo $h $s $v
end

function calculate_distance
    set -l h1 $argv[1]
    set -l s1 $argv[2]
    set -l v1 $argv[3]
    set -l h2 $argv[4]
    set -l s2 $argv[5]
    set -l v2 $argv[6]

    set -l hue_diff (math -s4 "min(abs($h1 - $h2), 360 - abs($h1 - $h2)) / 360")
    math -s4 "sqrt((5 * $hue_diff)^2 + (($s1 - $s2)^2) + (($v1 - $v2)^2))"
end

read -P "Enter hex color: " user_color
set user_color (string upper (string replace -r '^#' '' -- $user_color))

set user_rgb (hex_to_rgb "#$user_color")
set user_hsv (rgb_to_hsv $user_rgb[1] $user_rgb[2] $user_rgb[3])

set -g min_dist 1000
set -g closest_theme ""

for color in $tela_colors
    set theme (string split ' ' -f1 $color)
    set hex (string split ' ' -f2 $color)

    set theme_rgb (hex_to_rgb "#$hex")
    set theme_hsv (rgb_to_hsv $theme_rgb[1] $theme_rgb[2] $theme_rgb[3])

    set dist (calculate_distance \
        $user_hsv[1] $user_hsv[2] $user_hsv[3] \
        $theme_hsv[1] $theme_hsv[2] $theme_hsv[3])

    if test (math "$dist < $min_dist") -eq 1
        set min_dist $dist
        set closest_theme $theme
    end
end

echo "Closest theme: $closest_theme"

