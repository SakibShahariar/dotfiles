#!/usr/bin/env fish

# yt-tui.fish — YouTube downloader with TUI (Fish + Gum + FZF + Kitty)
# Dependencies: yt-dlp, fzf, gum, jq, ffmpeg, kitty

# --- Dependency Checks ---
function check_dep
    if not type -q $argv[1]
        echo "$argv[1] is not installed. Please install it first."
        exit 1
    end
end

check_dep "yt-dlp"
check_dep "fzf"
check_dep "ffmpeg"
check_dep "jq"
check_dep "kitty"
check_dep "gum"

# --- Gum styling ---
set -x GUM_CHOOSE_HEADER_FOREGROUND "#F92672"
set -x GUM_CHOOSE_CURSOR_FOREGROUND "#F92672"
set -x GUM_INPUT_PROMPT_FOREGROUND "#F92672"

# --- Get YouTube URL or Search ---
set INPUT_METHOD (gum choose "Enter URL" "Search YouTube")
if test -z "$INPUT_METHOD"
    echo "No input method chosen. Exiting."
    exit 1
end

set URL ""
if [ "$INPUT_METHOD" = "Enter URL" ]
    set URL (gum input --placeholder "Enter YouTube URL or Playlist...")
    if test -z "$URL"
        echo "No URL entered. Exiting."
        exit 1
    end

else
    set SEARCH_QUERY (gum input --placeholder "Enter search terms...")
    if test -z "$SEARCH_QUERY"
        echo "No search query entered. Exiting."
        exit 1
    end

    echo "🔍 Searching YouTube for '$SEARCH_QUERY'..."
    set SEARCH_RESULTS_RAW (yt-dlp "ytsearch10:$SEARCH_QUERY" --flat-playlist --print-json)
    if test -z "$SEARCH_RESULTS_RAW"
        echo "No results found. Exiting."
        exit 1
    end

    # Create temporary file with "Title<TAB>ID"
    set tmpfile (mktemp)
    echo "$SEARCH_RESULTS_RAW" | jq -r '[.title, .id] | @tsv' >> $tmpfile

    # --- Preview command: safe thumbnails without --place ---
    set preview_cmd '
        set id (echo {} | awk -F"\t" "{print \$2}")
        if test -n "$id"
            set thumb (yt-dlp "https://www.youtube.com/watch?v=$id" --skip-download --print-json \
                         | jq -r ".thumbnail // .thumbnails[0].url | select(.!=null)" \
                         | head -n1)
            if test -n "$thumb"
                # Auto-scaled preview (fits fzf preview window)
                kitty +kitten icat --silent --clear --transfer-mode=stream "$thumb"
            else
                echo "No thumbnail available."
            end
        else
            echo "Loading preview..."
        end
    '

    # fzf selection
    set selected_line (cat $tmpfile | \
        fzf --with-nth=1 \
            --delimiter="\t" \
            --preview $preview_cmd \
            --preview-window=right:40% \
            --height=80% \
            --layout=reverse \
            --border \
            --cycle \
            --prompt="Select video > ")

    kitty +kitten icat --clear
    rm -f $tmpfile

    if test -z "$selected_line"
        echo "No video selected. Exiting."
        exit 1
    end

    set VIDEO_ID (echo "$selected_line" | awk -F"\t" '{print $2}' | string trim)
    set URL "https://www.youtube.com/watch?v=$VIDEO_ID"
end

# --- Choose download type ---
set TYPE (gum choose "Audio" "Video")
if test -z "$TYPE"
    echo "No type chosen. Exiting."
    exit 1
end

# --- Format Selection ---
if [ "$TYPE" = "Audio" ]
    set FORMAT (gum choose "mp3" "flac" "wav" "m4a")
else
    set FORMAT (gum choose "best" "1080p" "720p" "480p")
end

# --- Confirmation ---
gum confirm "Download '$URL' as $TYPE ($FORMAT)?" || begin
    echo "Download cancelled."
    exit 0
end

# --- Destination ---
if [ "$TYPE" = "Audio" ]
    set DEST_DIR "$HOME/Music"
    set DEST_NAME "~/Music"
else
    set DEST_DIR "$HOME/Videos"
    set DEST_NAME "~/Videos"
end

mkdir -p "$DEST_DIR"
cd "$DEST_DIR"

# --- Construct yt-dlp command ---
set CMD "yt-dlp"
set ARGS "--no-warnings" "--progress"

if [ "$TYPE" = "Audio" ]
    set ARGS $ARGS "-x" "--audio-format" $FORMAT "--embed-thumbnail"
else
    if [ "$FORMAT" != "best" ]
        set ARGS $ARGS "-f" "bestvideo[height<=?$FORMAT][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"
    else
        set ARGS $ARGS "-f" "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"
    end
    set ARGS $ARGS "--embed-thumbnail"
end

set ARGS $ARGS "$URL"

# --- Download ---
echo
echo "⬇️  Downloading..."
$CMD $ARGS
echo
echo "✅ Download finished! Files are in $DEST_NAME."

