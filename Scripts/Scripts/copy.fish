#!/usr/bin/env fish

# Select multiple files with yad
set FILES (yad --file --multiple --separator='|' --title="📂 Select Files" --width=800 --height=500 --add-preview)

if test -z "$FILES"
    echo "❌ No files selected. Exiting..."
    exit 1
end

set DEST (yad --file --directory --title="📂 Select Destination Folder" --width=800 --height=500 --add-preview)

if test -z "$DEST"
    echo "❌ No destination folder selected. Exiting..."
    exit 1
end

echo -e "\033[34m📂 Selected Files:\033[0m"
for FILE in (string split '|' -- $FILES)
    echo -e "  \033[36m$FILE\033[0m"
end
echo -e "\n\033[34m📂 Destination Folder: \033[0m$DEST\n"

# Check if the destination is outside the home directory
if not string match -q "$HOME*" "$DEST"
    echo -e "\033[31m⚠️  Warning: Destination is outside your home directory. You may need to authenticate.\033[0m"
end

# Copying process with real-time progress
for FILE in (string split '|' -- $FILES)
    set BASENAME (basename -- "$FILE")
    set DEST_PATH "$DEST/$BASENAME"

    echo -e "\n📤  Copying:  \033[36m$BASENAME\033[0m →"

    # Check if authentication is needed
    if not string match -q "$HOME*" "$DEST"
        sudo rsync -ah --info=progress2 "$FILE" "$DEST_PATH"
    else
        rsync -ah --info=progress2 "$FILE" "$DEST_PATH"
    end

    # Check if the file was copied successfully
    if test -f "$DEST_PATH"
        echo -e "\033[32m✅  Copied:   $BASENAME\033[0m\n"
    else
        echo -e "\033[31m❌  Failed:   $BASENAME\033[0m\n"
    end
end

echo -e "🎉 Done!"
