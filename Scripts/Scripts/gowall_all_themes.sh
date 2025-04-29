#!/bin/bash

themes=$(gowall list)

input_path=$(zenity --file-selection --title="Select an Image" 2>/dev/null)

if [[ -z "$input_path" ]]; then
  echo "No file selected. Exiting..."
  exit 1
fi

while IFS= read -r theme; do
  gowall convert "$input_path" -t "$theme" -o "$theme"
done <<< "$themes"
