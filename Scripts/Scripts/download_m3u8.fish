#!/usr/bin/env fish
#
# download_m3u8.fish
# Download an M3U8 video (Patreon-friendly)
#
# Usage:
#   download_m3u8.fish <M3U8_URL> [OUTPUT_DIR]
#

# ───────────────────────────
# Dependency check
# ───────────────────────────
if not command -v yt-dlp >/dev/null
    echo "❌ yt-dlp not found."
    echo "   Install: pip install -U yt-dlp"
    exit 1
end

if not command -v gum >/dev/null
    echo "❌ gum not found."
    echo "   Install:"
    echo "   • Arch:    sudo pacman -S gum"
    echo "   • Fedora:  sudo dnf install gum"
    echo "   • Debian:  sudo apt install gum"
    exit 1
end

# ───────────────────────────
# Argument check
# ───────────────────────────
if not set -q argv[1]
    echo "Usage: download_m3u8.fish <M3U8_URL> [OUTPUT_DIR]"
    exit 1
end

set M3U8_URL $argv[1]

if not string match -qr '^https?://' "$M3U8_URL"
    echo "❌ Invalid URL. Needs http(s)."
    exit 1
end

if not string match -qr '\.m3u8' "$M3U8_URL"
    echo "⚠️  URL doesn't look like .m3u8 — continuing anyway."
end

# ───────────────────────────
# Output directory
# ───────────────────────────
if set -q argv[2]
    set output_dir $argv[2]
else
    set output_dir "$HOME/Videos"
end

mkdir -p "$output_dir" || begin
    echo "❌ Cannot create $output_dir"
    exit 1
end

# ───────────────────────────
# Filename logic
# ───────────────────────────
set clean_url (string split '?' "$M3U8_URL")[1]
set base_name (basename "$clean_url" .m3u8)

if test -z "$base_name"
    set base_name "patreon_video_"(date +%Y%m%d_%H%M%S)
end

# sanitize
set base_name (string replace -ra '[<>:"|?*/]' '_' "$base_name")

set ext ".mp4"
set output_path "$output_dir/$base_name$ext"
set part_file "$output_path.part"

# ───────────────────────────
# Existing file menu (gum)
# ───────────────────────────
if test -f "$output_path"
    set choice (gum choose \
        "Resume / overwrite" \
        "Create new file" \
        "Cancel" \
        --header "File already exists: "(basename "$output_path"))

    switch $choice
        case "Resume / overwrite"
            echo "↪ Resuming / overwriting"
        case "Create new file"
            set i 1
            while test -f "$output_path"
                set output_path "$output_dir/$base_name ($i)$ext"
                set part_file "$output_path.part"
                set i (math $i + 1)
            end
            echo "➕ New file:"
            echo "   $output_path"
        case "Cancel" ''
            echo "✖ Cancelled"
            exit 0
    end
end

# ───────────────────────────
# Partial download prompt (gum)
# ───────────────────────────
if test -f "$part_file"
    set r (gum choose \
        "Resume" \
        "Delete partial" \
        "Cancel" \
        --header "Partial download found: "(basename "$part_file"))

    switch $r
        case "Resume"
            echo "↪ Resuming partial"
        case "Delete partial"
            rm -f "$part_file"
            echo "🗑 Partial deleted"
        case "Cancel" ''
            exit 0
    end
end

# ───────────────────────────
# Disk space check (100MB)
# ───────────────────────────
set free_kb (df -k "$output_dir" | tail -1 | awk '{print $4}')
if test $free_kb -lt 102400
    echo "⚠️  Low disk space (<100MB)"
    echo -n "Continue? [y/N]: "
    read -l ok
    if not string match -qi 'y' "$ok"
        exit 0
    end
end

# ───────────────────────────
# Download
# ───────────────────────────
echo ""
echo "⬇️  Downloading…"
echo "Source: $M3U8_URL"
echo "Saved as: $output_path"
echo ""

yt-dlp \
    --add-header "Referer: https://www.patreon.com" \
    --add-header "User-Agent: Mozilla/5.0" \
    --retries 10 \
    --fragment-retries 10 \
    --concurrent-fragments 4 \
    --continue \
    --progress \
    -o "$output_path" \
    -- "$M3U8_URL"

set status_code $status
echo ""

# ───────────────────────────
# Result
# ───────────────────────────
if test $status_code -eq 0; and test -s "$output_path"
    echo "✅ Download complete."
    echo "📍 $output_path"
    du -h "$output_path"
else
    echo "❌ Download failed."
    if test -f "$part_file"
        echo "Partial kept:"
        du -h "$part_file"
        echo "Run again to resume."
    end
    exit 1
end
