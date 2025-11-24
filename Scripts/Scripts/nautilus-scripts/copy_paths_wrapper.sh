#!/usr/bin/env bash
# copy_paths_wrapper.sh
# Receives selected paths as args, prints them line-by-line to wl-copy and notifies.

if [ $# -eq 0 ]; then
  echo "NO_ARGS" > /tmp/copy_paths_wrapper.debug
  notify-send "Copy Path" "No files or folders selected."
  exit 1
fi

for p in "$@"; do
  printf "%s\n" "$p"
done | wl-copy

notify-send "Copy Path" "Path(s) copied to clipboard."
printf "%s\n" "$@" > /tmp/copy_paths_wrapper.debug
