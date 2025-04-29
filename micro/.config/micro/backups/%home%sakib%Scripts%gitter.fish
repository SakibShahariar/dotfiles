#!/usr/bin/env fish

# Define modern color scheme
set color_commit "\e[1;38;5;82m"      # Bold Green for commit
set color_push "\e[1;38;5;45m"        # Bold Blue for push
set color_files_header "\e[1;38;5;51m"  # Cyan for the header
set color_file_list "\e[1;38;5;15m"   # Bold White for file names
set color_added "\e[1;38;5;34m"       # Green for added
set color_deleted "\e[1;38;5;160m"    # Red for deleted
set color_modified "\e[1;38;5;220m"   # Yellow for modified
set color_renamed "\e[1;38;5;213m"    # Light Yellow for renamed
set color_reset "\e[0m"
set color_header "\e[1;38;5;99m"      # Purple-ish for headers

# Function to add smooth typing effect
function typewrite
    for arg in $argv
        for i in (seq (string length $arg))
            echo -n (string sub -s $i -l 1 $arg)
            sleep 0.03
        end
    end
    echo ""
end

# Ask for commit mode
set commit_mode (gum choose "Full directory" "Individual folder")

if test "$commit_mode" = "Full directory"
    echo -e "\n$color_header✨ $color_commit🟢 Staging everything...$color_reset"
    typewrite "Adding all changes in the directory..."
    git add .

    set commit_msg "commit"
    echo -e "\n$color_header✨ $color_commit✍️ Using default commit message: '$commit_msg'.$color_reset"
else
    set folder (gum file --directory --header "Pick a folder to commit")
    if test -z "$folder"
        echo -e "$color_deleted✖️ No folder selected. Exiting.$color_reset"
        exit 1
    end

    echo -e "\n$color_header✨ $color_commit🟢 Staging changes in '$folder'...$color_reset"
    git add $folder

    set commit_msg (gum input --placeholder "Enter commit message")
    if test -z "$commit_msg"
        set commit_msg "commit"
    end
end

# Check if anything is staged
set diff_output (git diff --name-status --cached)

if test -n "$diff_output"
    echo -e "\n$color_header✨ $color_commit✍️ Committing changes...$color_reset"
    git commit -m "$commit_msg"

    echo -e "\n$color_header✨ $color_push🚀 Pushing to main branch...$color_reset"
    typewrite "Sending your precious bytes to the cloud gods..."
    git push origin main

    echo -e "\n$color_header✨ $color_files_header📝 Files/Directories updated:$color_reset"
    echo -e "$color_files_header-----------------------------------------"

    for line in $diff_output
        set parts (string split \t $line)
        set file_status $parts[1]
        set file $parts[2]

        switch $file_status
            case A
                echo -e "$color_added• $file (Added)$color_reset"
            case M
                echo -e "$color_modified• $file (Modified)$color_reset"
            case D
                echo -e "$color_deleted• $file (Deleted)$color_reset"
            case "R*"
                set renamed_file (string split \t $line)[-1]
                echo -e "$color_renamed• $renamed_file (Renamed)$color_reset"
            case '*'
                echo -e "$color_file_list• $file (Other)$color_reset"
        end
    end
else
    echo -e "\n$color_files_header⚠️ No changes to commit.$color_reset"
end

# Farewell
echo -e "\n$color_header✨ $color_commit🎉 Boom! Commit & push complete.$color_reset"
