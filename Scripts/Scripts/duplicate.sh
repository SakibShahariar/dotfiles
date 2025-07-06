#!/bin/bash
for f in "$@"; do
  base="$(basename "$f")"
  dir="$(dirname "$f")"
  ext="${base##*.}"
  name="${base%.*}"
  if [ "$base" != "$ext" ]; then
    cp -r "$f" "$dir/$name (copy).$ext"
  else
    cp -r "$f" "$dir/$base (copy)"
  fi
done
