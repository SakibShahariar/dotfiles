#!/usr/bin/env fish

# Downloads a video from a URL, assuming it is from Patreon.
# Usage: download_m3u8.fish <M3U8_URL>

# --- Argument Check ---
if not set -q argv[1]
    echo "Usage: download_m3u8.fish <M3U8_URL>"
    exit 1
end
set M3U8_URL $argv[1]

# --- Path and Filename Logic ---
set url_no_query (string split '?' "$M3U8_URL")[1]
set filename (basename "$url_no_query" .m3u8).mp4
if [ "$filename" = ".mp4" ]
    set filename "video.mp4"
end

mkdir -p "$HOME/Videos"

# Check for duplicate filenames
set base_name (string replace -r '\.mp4$' '' $filename)
set ext ".mp4"
set counter 1
set output_path "$HOME/Videos/$filename"
while test -f "$output_path"
    set output_path "$HOME/Videos/$base_name ($counter)$ext"
    set counter (math $counter + 1)
end

# --- Download ---
echo "⬇️  Starting download from Patreon..."
echo "   Source: $M3U8_URL"
echo "   Destination: $output_path"

yt-dlp \
    --add-header "Referer: https://www.patreon.com" \
    -o "$output_path" \
    -- "$M3U8_URL"

if test $status -eq 0
    echo "✅ Download finished: $output_path"
else
    echo "❌ Download failed." >&2
    exit 1
end
