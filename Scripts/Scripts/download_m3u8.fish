#!/usr/bin/env fish

# Check if argument is given
if not set -q argv[1]
    echo "Usage: download_m3u8.fish <M3U8_URL>"
    exit 1
end

set M3U8_URL $argv[1]

# Output filename (extract basename or default to patreon_video)
set FILENAME (basename $M3U8_URL)
set FILENAME (string replace ".m3u8" ".mp4" $FILENAME)
set OUTPUT "~/Videos/$FILENAME"

# Create output dir if it doesn't exist
mkdir -p ~/Videos

# Download using yt-dlp with Referer header
yt-dlp \
    "$M3U8_URL" \
    --add-header "Referer: https://www.patreon.com" \
    -f bestvideo+bestaudio \
    -o "$OUTPUT"

echo "✅ Download finished: $OUTPUT"
