#!/usr/bin/env fish

# Use Zenity to get a list of .ts files
set input_files (zenity --file-selection --multiple --title="Select TS Files" --file-filter="*.ts")

# Check if any files were selected
if test -z "$input_files"
    zenity --error --text="No files selected!"
    exit 1
end

# Split the input_files string into an array
set input_files_array (string split '|' "$input_files")

# Get the total number of files
set total_files (count $input_files_array)

# Initialize a counter
set counter 0

# Convert the files to MP4
for file in $input_files_array
    # Trim any leading or trailing whitespace from the filename
    set file (string trim "$file")

    # Construct the output file name by replacing .ts with .mp4
    set output_file (string replace -r '\.ts$' '.mp4' $file)

    # Run ffmpeg to convert the file, suppressing most output
    ffmpeg -loglevel warning -i "$file" -c:v copy -c:a copy "$output_file"

    # Check for success or failure of the conversion
    if test $status -ne 0
        zenity --error --text="Error converting $file"
    else
        # If the conversion was successful, delete the original file
        rm "$file"

        # Show success message with auto-close
        zenity --info --text="Successfully converted $file to $output_file" --timeout=2
    end

    # Update the counter for progress (if you still want to use progress handling)
    set counter (math $counter + 1)
end

# Final message (optional)
zenity --info --text="All conversions complete!" --timeout=2 
