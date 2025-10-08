#!/bin/bash
# v2: Handles multiple copies and hidden files correctly.

for f in "$@"; do
  dir="$(dirname "$f")"
  base="$(basename "$f")"

  # Determine base name and extension more robustly
  if [[ "$base" == *.* && "${base%.*}" != "" ]]; then
    ext=".${base##*.}"
    name="${base%.*}"
  else
    ext=""
    name="$base"
  fi

  # Find a unique filename for the copy
  counter=1
  # First, try creating "(copy)"
  dest="$dir/$name(copy)$ext"

  # If it exists, start trying "(copy 2)", "(copy 3)", etc.
  while [ -e "$dest" ]; do
    counter=$((counter + 1))
    dest="$dir/$name (copy $counter)$ext"
  done

  echo "Copying '$f' to '$dest'"
  cp -r "$f" "$dest"
done
