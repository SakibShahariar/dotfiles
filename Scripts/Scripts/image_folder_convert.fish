#!/usr/bin/env fish

# Prompt user to select a folder using a file picker
set folder (zenity --file-selection --directory --title="Select Folder with Images")

# Check if a folder was selected
if test -z "$folder"
    notify-send "Image Conversion" "No folder selected. Exiting..." --icon=dialog-error
    exit 1
end

# Loop through all image files in the selected folder
for img in $folder/*
    # Check if the file is an image
    if file --mime-type "$img" | grep -q 'image/'
        # Generate output file path with .jpg extension
        set output (string replace -r '\.[^.]*$' '.jpg' $img)

        # Convert the image to JPG
        gowall convert "$img" -f jpg "$output"

        # Notify success or failure
        if test $status -eq 0
            notify-send "Image Conversion" "Converted: $img → $output" --icon=dialog-information
        else
            notify-send "Image Conversion" "Failed to convert: $img" --icon=dialog-error
        end
    end
end
