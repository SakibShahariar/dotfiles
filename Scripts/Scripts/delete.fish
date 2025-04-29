#!/usr/bin/env fish

# Select multiple files with yad
set FILES (yad --file --multiple --separator='|' --title="📂 Select Files to Delete" --width=800 --height=500 --add-preview)

if test -z "$FILES"
    echo "❌ No files selected. Exiting..."
    exit 1
end

echo -e "\033[34m📂 Selected Files for Deletion:\033[0m"
for FILE in (string split '|' -- $FILES)
    echo -e "  \033[36m$FILE\033[0m"
end
echo -e "\n"

# Deletion process
for FILE in (string split '|' -- $FILES)
    echo -e "\n📤  Deleting:  \033[36m$FILE\033[0m →"

    # Check if authentication is needed (deleting outside home directory)
    if not string match -q "$HOME*" "$FILE"
        sudo rm -v "$FILE"
    else
        rm -v "$FILE"
    end

    # Check if the file was deleted successfully
    if not test -e "$FILE"
        echo -e "\033[32m✅  Deleted:   $FILE\033[0m\n"
    else
        echo -e "\033[31m❌  Failed:   $FILE\033[0m\n"
    end
end

echo -e "🎉 Done!"
