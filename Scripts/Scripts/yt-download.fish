#!/usr/bin/env fish
#
# yt-download.fish — YouTube downloader with TUI
# Fish + Gum + FZF + yt-dlp
#
# MODE: Fake album metadata for non-music videos
# RESULT: Nautilus-visible thumbnails + sane tags
#

# ==================== Dependency Checks ====================
function check_dep
    if not type -q $argv[1]
        echo "❌ $argv[1] is not installed."
        exit 1
    end
end

for dep in yt-dlp fzf ffmpeg jq gum
    check_dep $dep
end

# ==================== Helpers ====================
function must_exist
    test -z "$argv[1]"; and exit 1
end

# ==================== Gum Styling ====================
set -x GUM_CHOOSE_HEADER_FOREGROUND "#F92672"
set -x GUM_CHOOSE_CURSOR_FOREGROUND "#F92672"
set -x GUM_INPUT_PROMPT_FOREGROUND "#F92672"

# ==================== Input ====================
set INPUT_METHOD (gum choose "Enter URL" "Search YouTube")
must_exist "$INPUT_METHOD"

set URL ""

if test "$INPUT_METHOD" = "Enter URL"
    set URL (gum input --placeholder "Enter YouTube URL")
    must_exist "$URL"
else
    set QUERY (gum input --placeholder "Search YouTube")
    must_exist "$QUERY"

    set RAW (yt-dlp "ytsearch10:$QUERY" --flat-playlist --print-json)
    must_exist "$RAW"

    set tmp (mktemp)
    echo "$RAW" | jq -r '[.title, .id] | @tsv' > $tmp

    set PICK (cat $tmp | fzf --with-nth=1 --delimiter="\t")
    rm -f $tmp
    must_exist "$PICK"

    set VID (echo "$PICK" | awk -F"\t" '{print $2}')
    set URL "https://www.youtube.com/watch?v=$VID"
end

# ==================== Metadata ====================
set TITLE (yt-dlp --print "%(title)s" --skip-download "$URL")
set CREATOR (yt-dlp --print "%(uploader)s" --skip-download "$URL")

# Fake album (constant, clean)
set FAKE_ALBUM "YouTube Singles"

# ==================== Media Type ====================
set TYPE (gum choose "Audio" "Video")
must_exist "$TYPE"

# ==================== Format ====================
if test "$TYPE" = "Audio"
    set FORMAT (gum choose mp3 m4a flac)
else
    set FORMAT (gum choose best 1080 720 480)
end
must_exist "$FORMAT"

# ==================== Destination ====================
if test "$TYPE" = "Audio"
    set DEST "$HOME/Music"
else
    set DEST "$HOME/Videos"
end

mkdir -p "$DEST"
cd "$DEST"

# ==================== yt-dlp Args ====================
set ARGS \
    --no-warnings \
    --progress \
    --add-metadata \
    --metadata "title=$TITLE" \
    --metadata "artist=$CREATOR" \
    --metadata "album=$FAKE_ALBUM" \
    -o "%(artist)s - %(title)s.%(ext)s"

if test "$TYPE" = "Audio"
    set ARGS $ARGS \
        -x \
        --audio-format $FORMAT \
        --embed-metadata \
        --embed-thumbnail \
        --postprocessor-args "-id3v2_version 3"
else
    set ARGS $ARGS -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best"
end

set ARGS $ARGS "$URL"

# ==================== Summary ====================
gum style \
  --border rounded \
  --padding "1 2" \
  --border-foreground "#F92672" \
  "🎬 Title: $TITLE
🎤 Artist: $CREATOR
💿 Album: $FAKE_ALBUM
📦 Type: $TYPE
📂 Save to: $DEST"

# ==================== Execute ====================
gum confirm "Download now?"; or exit 0

echo "⬇️  Downloading…"
yt-dlp $ARGS

echo "✅ Done. Album metadata forged. Nautilus fooled successfully."

