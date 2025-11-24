#!/usr/bin/env fish
# video_to_mp3_tui_with_cover_and_metadata.fish
# Interactive Fish TUI for converting any video to MP3 with embedded cover image and metadata

function ensure_cmd --description 'Ensure a command exists or exit with message'
    set cmd $argv[1]
    if not type -q $cmd
        echo "Required command '$cmd' not found. Install it and re-run."
        exit 1
    end
end

ensure_cmd ffmpeg

set HAS_GUM (type -q gum; and echo yes; or echo no)
set HAS_FZF (type -q fzf; and echo yes; or echo no)

function pick_file
    if test $HAS_GUM = yes
        set file (gum file)
        if test -z "$file"
            echo "No file selected."; exit 1
        end
        echo $file
    else if test $HAS_FZF = yes
        set file (ls -1 | fzf --height 40% --border --prompt "Pick video: ")
        if test -z "$file"; echo "No file selected."; exit 1; end
        echo (realpath $file)
    else
        printf "Enter path to video file: "
        read file
        if test -z "$file" -o ! -f "$file"
            echo "File not found or empty."; exit 1
        end
        echo (realpath $file)
    end
end

function choose_output_name
    set infile $argv[1]
    set base (basename "$infile" | string replace -r '\\.[^.]+$' '')

    if test $HAS_GUM = yes
        set outname (gum input --placeholder "Output filename" --value "$base")
    else
        printf "Output filename [%s]: " "$base"
        read outname
        and test -z "$outname"; and set outname $base
    end

    set outdir ~/Music
    mkdir -p -- $outdir
    echo "$outdir/$outname.mp3"
end

function choose_bitrate
    set options 128k 192k 256k 320k
    if test $HAS_GUM = yes
        set bitrate (gum choose --cursor dot --limit 1 $options)
    else
        echo "Choose bitrate (128k,192k,256k,320k):"
        read bitrate
        and test -z "$bitrate"; and set bitrate 192k
    end
    echo $bitrate
end

function convert_to_mp3_with_cover_and_metadata
    set infile $argv[1]
    set outfile $argv[2]
    set bitrate $argv[3]
    set logfile (mktemp /tmp/video_to_mp3_log.XXXXXX)
    set tmpcover (mktemp /tmp/cover.XXXXXX.jpg)

    echo "Extracting cover image from video..."
    ffmpeg -ss 00:00:02 -i "$infile" -frames:v 1 -q:v 2 "$tmpcover" -y > /dev/null 2>&1

    # Extract basic metadata (title, artist, album) from video if available
    set title (ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$infile")
    set artist (ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$infile")
    set album (ffprobe -v error -show_entries format_tags=album -of default=noprint_wrappers=1:nokey=1 "$infile")

    # Fallbacks
    if test -z "$title"
        set title (basename "$infile" | string replace -r '\\.[^.]+$' '')
    end

    echo "Converting '$infile' to MP3 -> '$outfile' at $bitrate with embedded cover and metadata"
    ffmpeg -i "$infile" -i "$tmpcover" -map 0:a -map 1 \
        -c:a libmp3lame -b:a $bitrate -id3v2_version 3 \
        -metadata title="$title" \
        -metadata artist="$artist" \
        -metadata album="$album" \
        -metadata:s:v title="Album cover" \
        -metadata:s:v comment="Cover (front)" \
        "$outfile" >"$logfile" 2>&1

    if test $status -ne 0
        echo "Conversion failed. Tail of ffmpeg log:"; echo '---'; tail -n 60 "$logfile"; echo '---'
    else
        echo "Done: $outfile"
    end

    rm -f "$logfile" "$tmpcover"
end

function main
    set infile (pick_file)
    set outfile (choose_output_name $infile)
    set bitrate (choose_bitrate)

    convert_to_mp3_with_cover_and_metadata "$infile" "$outfile" "$bitrate"
end

main
