#!/usr/bin/env fish

function hex_to_rgb
  set hex (string replace -r '^#' '' $argv[1])
  set r (math "ibase=16; 0x"(string sub -s 1 -l 2 $hex))
  set g (math "ibase=16; 0x"(string sub -s 3 -l 2 $hex))
  set b (math "ibase=16; 0x"(string sub -s 5 -l 2 $hex))
  echo "$r $g $b"
end

function rgb_to_hex
  set r (printf "%02x" $argv[1])
  set g (printf "%02x" $argv[2])
  set b (printf "%02x" $argv[3])
  echo "#$r$g$b"
end

function brightness
  set rgb (hex_to_rgb $argv[1])
  math "0.299 * $rgb[1] + 0.587 * $rgb[2] + 0.114 * $rgb[3]"
end

function blend_colors
  set total_r 0
  set total_g 0
  set total_b 0
  set count (count $argv)

  for color in $argv
    set rgb (hex_to_rgb $color)
    set total_r (math "$total_r + $rgb[1]")
    set total_g (math "$total_g + $rgb[2]")
    set total_b (math "$total_b + $rgb[3]")
  end

  set avg_r (math "round($total_r / $count)")
  set avg_g (math "round($total_g / $count)")
  set avg_b (math "round($total_b / $count)")

  rgb_to_hex $avg_r $avg_g $avg_b
end
