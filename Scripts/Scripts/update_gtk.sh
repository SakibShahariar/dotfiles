#!/bin/bash

# Define the source file
SOURCE="/home/sakib/.config/gtk-4.0/gtk.css"

# Define the destination files in an array
DESTINATIONS=(
    "/home/sakib/.config/gtk-4.0/gtk-dark.css"
    "/home/sakib/Material-Gnome/gtk-4.0/gtk-dark.css"
    "/home/sakib/Material-Gnome/gtk-4.0/gtk.css"
    "/home/sakib/Material-Gnome/.themes/Material-Gnome/gtk-4.0/gtk-dark.css"
    "/home/sakib/Material-Gnome/.themes/Material-Gnome/gtk-4.0/gtk.css"
    "/home/sakib/software/Material-Gnome/gtk-4.0/gtk.css"
    "/home/sakib/software/Material-Gnome/gtk-4.0/gtk-dark.css"
)

# Check if the source file exists
if [ ! -f "$SOURCE" ]; then
    echo "Error: Source file $SOURCE does not exist."
    exit 1
fi

echo "Copying config to destinations..."

# Loop through each destination and copy the file
for DEST in "${DESTINATIONS[@]}"; do
    # Extract the directory path from the full file path
    DIR=$(dirname "$DEST")

    # Create the directory if it doesn't exist
    mkdir -p "$DIR"

    # Copy the file
    cp "$SOURCE" "$DEST"
    echo "  -> Copied to: $DEST"
done

echo "Done! All files updated successfully."
