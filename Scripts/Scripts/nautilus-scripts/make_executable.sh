#!/usr/bin/env bash
# make_executable.sh — makes selected files executable, with notification

if [ $# -eq 0 ]; then
    notify-send "Make Executable" "No files or folders selected."
    exit 1
fi

count=0
for f in "$@"; do
    chmod +x "$f"
    count=$((count+1))
done

notify-send "Make Executable" "$count file(s) made executable."
