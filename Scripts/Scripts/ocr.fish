#!/usr/bin/env fish

# File picker to choose the input file
set input_file (zenity --file-selection --title="Select an image for OCR" --file-filter="Images | *.png *.jpg *.jpeg *.bmp *.tiff")

# Check if the user canceled the file picker
if test -z "$input_file"
    echo "No file selected. Exiting."
    exit 1
end

# Output file for OCR
set output_file /tmp/ocr_result.txt

# Run OCR using Tesseract
tesseract "$input_file" "$output_file:t"

# Check if Tesseract succeeded
if test $status -ne 0
    echo "OCR failed. Ensure Tesseract is installed and the selected file is valid."
    exit 1
end

# Display the resulting text in the terminal
echo "OCR completed. Showing the result:"
echo "-----------------------------------"
cat "$output_file"
echo "-----------------------------------"
